import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/actions/querya_schema_object_loader.dart';
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/ui/querya_shell_status.dart';
import 'package:querya_desktop/core/unsaved_work_guard.dart';
import 'package:querya_desktop/features/command_palette/quick_switcher_dialog.dart';
import 'package:querya_desktop/features/main_screen/main_screen_workspace_state.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart' show SqliteObjectKind;
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/mysql/mysql_sql_tx_guard.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_tx_guard.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_tx_guard.dart';

/// What the user picked in the connections tree or the quick switcher, applied
/// to [workspace]: each pick first asks to keep or discard unsaved work, and a
/// pick of what is open already does nothing.
///
/// The screen owns the notifier and the context; this holds the rules.
class MainScreenNavigator {
  MainScreenNavigator({
    required this.workspace,
    required BuildContext Function() context,
    required bool Function() mounted,
    required VoidCallback onPendingMongoCollectionChanged,
  })  : _context = context,
        _mounted = mounted,
        _onPendingMongoCollectionChanged = onPendingMongoCollectionChanged;

  final ValueNotifier<MainScreenWorkspaceState> workspace;
  final BuildContext Function() _context;
  final bool Function() _mounted;
  final VoidCallback _onPendingMongoCollectionChanged;

  /// The collection picked in the tree, until the workspace shows it.
  String? pendingMongoCollection;

  void _setPendingMongoCollection(String? value) {
    if (pendingMongoCollection == value) return;
    pendingMongoCollection = value;
    _onPendingMongoCollectionChanged();
  }

  Future<bool> allowUnsavedNavigation() {
    return confirmDiscardUnsavedWorkIfNeeded(_context());
  }

  void onConnectionSelected(ConnectionRow connection) {
    unawaited(selectConnection(connection));
  }

  Future<void> selectConnection(ConnectionRow connection) async {
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    final prevId = workspace.value.activeConnection?.id;
    workspace.value = workspace.value.selectConnection(connection);
    if (prevId != connection.id) {
      QueryaShellStatus.instance.clear();
      _setPendingMongoCollection(null);
    }
    final id = connection.id;
    if (id != null) {
      unawaited(AppSettings.instance.recordRecentConnection(id));
    }
  }

  void onPostgresObjectSelected(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) {
    unawaited(selectPostgresObject(
      connection,
      database,
      schema,
      name,
      kind,
    ));
  }

  Future<void> selectPostgresObject(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) async {
    final ws = workspace.value;
    final cur = ws.selectedPostgresObject;
    final same = ws.activeConnection?.id == connection.id &&
        cur != null &&
        cur.database == database &&
        cur.schema == schema &&
        cur.name == name &&
        cur.kind == kind;
    if (same) return;
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    if (!await confirmOpenPostgresTableIfSqlTx(
      _context(),
      connection: connection,
      database: database,
      kind: kind,
    )) {
      return;
    }
    if (!_mounted()) return;
    workspace.value = workspace.value.selectPostgresObject(
      connection,
      database,
      schema,
      name,
      kind,
    );
  }

  void onMysqlObjectSelected(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  ) {
    unawaited(selectMysqlObject(connection, database, name, kind));
  }

  Future<void> selectMysqlObject(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  ) async {
    final ws = workspace.value;
    final cur = ws.selectedMysqlObject;
    final same = ws.activeConnection?.id == connection.id &&
        cur != null &&
        cur.database == database &&
        cur.name == name &&
        cur.kind == kind;
    if (same) return;
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    if (!await confirmOpenMysqlTableIfSqlTx(
      _context(),
      connection: connection,
      database: database,
      kind: kind,
    )) {
      return;
    }
    if (!_mounted()) return;
    workspace.value = workspace.value.selectMysqlObject(
      connection,
      database,
      name,
      kind,
    );
  }

  void onRedisDatabaseSelected(ConnectionRow connection, int database) {
    unawaited(selectRedisDatabase(connection, database));
  }

  Future<void> selectRedisDatabase(
    ConnectionRow connection,
    int database,
  ) async {
    final ws = workspace.value;
    if (ws.activeConnection?.id == connection.id &&
        ws.activeRedisDb == database) {
      return;
    }
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    workspace.value = workspace.value.selectRedisDb(connection, database);
  }

  void onMongoDBDatabaseSelected(ConnectionRow connection, String database) {
    unawaited(selectMongoDatabase(connection, database));
  }

  Future<void> selectMongoDatabase(
    ConnectionRow connection,
    String database,
  ) async {
    final ws = workspace.value;
    if (ws.activeConnection?.id == connection.id &&
        ws.activeMongoDB == database &&
        ws.selectedMongoCollection == null) {
      return;
    }
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    _setPendingMongoCollection(null);
    workspace.value = workspace.value.selectMongoDb(connection, database);
  }

  void onMongoCollectionSelected(
    ConnectionRow connection,
    String database,
    String collection,
  ) {
    unawaited(selectMongoCollection(connection, database, collection));
  }

  Future<void> selectMongoCollection(
    ConnectionRow connection,
    String database,
    String collection,
  ) async {
    final ws = workspace.value;
    if (ws.activeConnection?.id == connection.id &&
        ws.activeMongoDB == database &&
        ws.selectedMongoCollection == collection) {
      return;
    }
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    _setPendingMongoCollection(collection);
    workspace.value =
        workspace.value.selectMongoCollection(connection, database, collection);
  }

  void onPostgresOpenSqlWorkspace(
    ConnectionRow connection, {
    String? database,
    String? schema,
    String? name,
    PostgresObjectKind? kind,
  }) {
    unawaited(openPostgresSqlWorkspace(
      connection,
      database: database,
      schema: schema,
      name: name,
      kind: kind,
    ));
  }

  Future<void> openPostgresSqlWorkspace(
    ConnectionRow connection, {
    String? database,
    String? schema,
    String? name,
    PostgresObjectKind? kind,
  }) async {
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    workspace.value = workspace.value.openPostgresSqlWorkspace(
      connection,
      seedDatabase: database,
      seedSchema: schema,
      seedName: name,
      seedKind: kind,
    );
  }

  void onMysqlOpenSqlWorkspace(ConnectionRow connection) {
    unawaited(openMysqlSqlWorkspace(connection));
  }

  Future<void> openMysqlSqlWorkspace(ConnectionRow connection) async {
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    workspace.value = workspace.value.openMysqlSqlWorkspace(connection);
  }

  void onSqliteObjectSelected(
    ConnectionRow connection,
    String name,
    SqliteObjectKind kind,
  ) {
    unawaited(selectSqliteObject(connection, name, kind));
  }

  Future<void> selectSqliteObject(
    ConnectionRow connection,
    String name,
    SqliteObjectKind kind,
  ) async {
    final ws = workspace.value;
    final cur = ws.selectedSqliteObject;
    final same = ws.activeConnection?.id == connection.id &&
        cur != null &&
        cur.name == name &&
        cur.kind == kind;
    if (same) return;
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    if (!await confirmOpenSqliteTableIfSqlTx(
      _context(),
      connection: connection,
      kind: kind,
    )) {
      return;
    }
    if (!_mounted()) return;
    workspace.value = workspace.value.selectSqliteObject(
      connection,
      name,
      kind,
    );
  }

  void onSqliteOpenSqlWorkspace(ConnectionRow connection) {
    unawaited(openSqliteSqlWorkspace(connection));
  }

  Future<void> openSqliteSqlWorkspace(ConnectionRow connection) async {
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    workspace.value = workspace.value.openSqliteSqlWorkspace(connection);
  }

  void onExtensionObjectSelected(
    ConnectionRow connection,
    String database,
    String name,
  ) {
    unawaited(selectExtensionObject(connection, database, name));
  }

  Future<void> selectExtensionObject(
    ConnectionRow connection,
    String database,
    String name,
  ) async {
    final ws = workspace.value;
    final cur = ws.selectedExtensionObject;
    final same = ws.activeConnection?.id == connection.id &&
        cur != null &&
        cur.database == database &&
        cur.name == name;
    if (same) return;
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    workspace.value = workspace.value.selectExtensionObject(
      connection,
      database,
      name,
    );
  }

  void openQuickSwitcher([String query = '']) {
    final ctx = FocusManager.instance.primaryFocus?.context ?? _context();
    final ws = workspace.value;
    final conn = ws.activeConnection;
    unawaited(showQuickSwitcher(
      ctx,
      initialQuery: query,
      load: () => QueryaSchemaObjectLoader.load(
        connection: conn,
        database: ws.selectedPostgresObject?.database ??
            ws.selectedMysqlObject?.database ??
            ws.selectedExtensionObject?.database ??
            conn?.databaseName,
        mongoDatabase: ws.activeMongoDB ?? conn?.databaseName,
      ),
    ));
  }

  void onOpenSchemaObject(QueryaSchemaObject object) {
    final conn = workspace.value.activeConnection;
    if (conn == null) return;
    final type = conn.type.toLowerCase();
    switch (object.kind) {
      case QueryaSchemaObjectKind.table:
      case QueryaSchemaObjectKind.view:
      case QueryaSchemaObjectKind.materializedView:
        if (type == 'postgres' || type == 'postgresql') {
          onPostgresObjectSelected(
            conn,
            object.database ?? conn.databaseName ?? '',
            object.schema ?? 'public',
            object.name,
            switch (object.kind) {
              QueryaSchemaObjectKind.view => PostgresObjectKind.view,
              QueryaSchemaObjectKind.materializedView =>
                PostgresObjectKind.materializedView,
              _ => PostgresObjectKind.table,
            },
          );
          return;
        }
        if (type == 'mysql') {
          onMysqlObjectSelected(
            conn,
            object.database ?? conn.databaseName ?? '',
            object.name,
            object.kind == QueryaSchemaObjectKind.view
                ? MysqlObjectKind.view
                : MysqlObjectKind.table,
          );
          return;
        }
        if (type == 'sqlite') {
          onSqliteObjectSelected(
            conn,
            object.name,
            object.kind == QueryaSchemaObjectKind.view
                ? SqliteObjectKind.view
                : SqliteObjectKind.table,
          );
          return;
        }
        if (conn.isExtensionDriver) {
          onExtensionObjectSelected(
            conn,
            object.database ?? conn.databaseName ?? '',
            object.name,
          );
        }
      case QueryaSchemaObjectKind.collection:
        onMongoCollectionSelected(
          conn,
          object.database ?? conn.databaseName ?? '',
          object.name,
        );
    }
  }

  void openSqlWorkspaceForConnection(ConnectionRow connection) {
    switch (connection.type) {
      case 'postgresql':
        onPostgresOpenSqlWorkspace(connection);
      case 'mysql':
        onMysqlOpenSqlWorkspace(connection);
      case 'sqlite':
        onSqliteOpenSqlWorkspace(connection);
      default:
        if (ExtensionDriverCatalog.isExtensionDriverConnection(connection)) {
          unawaited(selectConnection(connection));
        }
    }
  }

  void onGoHome() {
    unawaited(goHome());
  }

  Future<void> goHome() async {
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    workspace.value = MainScreenWorkspaceState.empty;
    QueryaShellStatus.instance.clear();
  }

  Future<void> closeWorkspace() async {
    if (!await allowUnsavedNavigation()) return;
    if (!_mounted()) return;
    workspace.value = workspace.value.unselectActiveObject();
  }

  bool hasCloseableWorkspace(MainScreenWorkspaceState ws) {
    return ws.selectedPostgresObject != null ||
        ws.selectedMysqlObject != null ||
        ws.selectedSqliteObject != null ||
        ws.selectedExtensionObject != null ||
        ws.activeMongoDB != null ||
        ws.activeRedisDb != null;
  }
}
