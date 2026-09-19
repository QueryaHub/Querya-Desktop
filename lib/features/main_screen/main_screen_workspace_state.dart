import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart' show SqliteObjectKind;
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';

/// Workspace / tree selection shown in [WorkspacePanel] and [ConnectionsPanel].
@immutable
class MainScreenWorkspaceState {
  const MainScreenWorkspaceState({
    this.activeConnection,
    this.activeRedisDb,
    this.activeMongoDB,
    this.selectedPostgresObject,
    this.postgresSqlTabRequestToken = 0,
    this.postgresSqlEditorContext,
    this.postgresSqlEditorContextToken = 0,
    this.selectedMysqlObject,
    this.mysqlSqlTabRequestToken = 0,
    this.selectedSqliteObject,
    this.sqliteSqlTabRequestToken = 0,
    this.selectedExtensionObject,
    this.lastSelectedPostgresObject,
    this.lastSelectedMysqlObject,
    this.lastSelectedSqliteObject,
    this.lastSelectedExtensionObject,
    this.lastSelectedMongoDb,
    this.lastSelectedRedisDb,
    this.isReadOnly = false,
  });

  final ConnectionRow? activeConnection;
  final int? activeRedisDb;
  final String? activeMongoDB;
  final ({
    String database,
    String schema,
    String name,
    PostgresObjectKind kind
  })? selectedPostgresObject;
  final int postgresSqlTabRequestToken;

  /// Seeds the SQL editor when using "Open in SQL" (table/view/matview from current tree selection).
  final ({
    String database,
    String schema,
    String name,
    PostgresObjectKind kind
  })? postgresSqlEditorContext;
  final int postgresSqlEditorContextToken;
  
  final ({
    String database,
    String name,
    MysqlObjectKind kind
  })? selectedMysqlObject;
  final int mysqlSqlTabRequestToken;

  final ({
    String name,
    SqliteObjectKind kind
  })? selectedSqliteObject;
  final int sqliteSqlTabRequestToken;

  /// Table/view selected in the sidebar tree of an extension driver connection.
  final ({
    String database,
    String name,
  })? selectedExtensionObject;

  /// Remembers the last visited table/view for the active connection to support 1-click return from stats.
  final ({
    String database,
    String schema,
    String name,
    PostgresObjectKind kind
  })? lastSelectedPostgresObject;

  final ({
    String database,
    String name,
    MysqlObjectKind kind
  })? lastSelectedMysqlObject;

  final ({
    String name,
    SqliteObjectKind kind
  })? lastSelectedSqliteObject;

  final ({
    String database,
    String name,
  })? lastSelectedExtensionObject;

  /// Last MongoDB database opened for 1-click return from server stats.
  final String? lastSelectedMongoDb;

  /// Last Redis database index opened for 1-click return from server stats.
  final int? lastSelectedRedisDb;

  final bool isReadOnly;

  static const empty = MainScreenWorkspaceState();

  MainScreenWorkspaceState toggleReadOnly() {
    return MainScreenWorkspaceState(
      activeConnection: activeConnection,
      activeRedisDb: activeRedisDb,
      activeMongoDB: activeMongoDB,
      selectedPostgresObject: selectedPostgresObject,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: postgresSqlEditorContext,
      postgresSqlEditorContextToken: postgresSqlEditorContextToken,
      selectedMysqlObject: selectedMysqlObject,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: selectedSqliteObject,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      selectedExtensionObject: selectedExtensionObject,
      lastSelectedPostgresObject: lastSelectedPostgresObject,
      lastSelectedMysqlObject: lastSelectedMysqlObject,
      lastSelectedSqliteObject: lastSelectedSqliteObject,
      lastSelectedExtensionObject: lastSelectedExtensionObject,
      lastSelectedMongoDb: lastSelectedMongoDb,
      lastSelectedRedisDb: lastSelectedRedisDb,
      isReadOnly: !isReadOnly,
    );
  }

  MainScreenWorkspaceState selectConnection(ConnectionRow connection) {
    final same = activeConnection?.id == connection.id;
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: null,
      postgresSqlEditorContextToken: 0,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: null,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      selectedExtensionObject: null,
      lastSelectedPostgresObject:
          same ? (selectedPostgresObject ?? lastSelectedPostgresObject) : null,
      lastSelectedMysqlObject:
          same ? (selectedMysqlObject ?? lastSelectedMysqlObject) : null,
      lastSelectedSqliteObject:
          same ? (selectedSqliteObject ?? lastSelectedSqliteObject) : null,
      lastSelectedExtensionObject: same
          ? (selectedExtensionObject ?? lastSelectedExtensionObject)
          : null,
      lastSelectedMongoDb:
          same ? (activeMongoDB ?? lastSelectedMongoDb) : null,
      lastSelectedRedisDb:
          same ? (activeRedisDb ?? lastSelectedRedisDb) : null,
      isReadOnly: false,
    );
  }

  /// Clears the active table/view/db selection to show server stats/home, but retains
  /// the reference in [lastSelectedPostgresObject] etc. so users can return in 1 click.
  MainScreenWorkspaceState unselectActiveObject() {
    return MainScreenWorkspaceState(
      activeConnection: activeConnection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: postgresSqlEditorContext,
      postgresSqlEditorContextToken: postgresSqlEditorContextToken,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: null,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      selectedExtensionObject: null,
      lastSelectedPostgresObject:
          selectedPostgresObject ?? lastSelectedPostgresObject,
      lastSelectedMysqlObject:
          selectedMysqlObject ?? lastSelectedMysqlObject,
      lastSelectedSqliteObject:
          selectedSqliteObject ?? lastSelectedSqliteObject,
      lastSelectedExtensionObject:
          selectedExtensionObject ?? lastSelectedExtensionObject,
      lastSelectedMongoDb: activeMongoDB ?? lastSelectedMongoDb,
      lastSelectedRedisDb: activeRedisDb ?? lastSelectedRedisDb,
      isReadOnly: isReadOnly,
    );
  }

  /// Restores the last visited table/view for the active connection.
  MainScreenWorkspaceState restoreLastSelectedObject() {
    final conn = activeConnection;
    if (conn == null) return this;
    final type = conn.type.toLowerCase();
    switch (type) {
      case 'postgres':
      case 'postgresql':
        if (lastSelectedPostgresObject != null) {
          final obj = lastSelectedPostgresObject!;
          return selectPostgresObject(
            conn,
            obj.database,
            obj.schema,
            obj.name,
            obj.kind,
          );
        }
        break;
      case 'mysql':
        if (lastSelectedMysqlObject != null) {
          final obj = lastSelectedMysqlObject!;
          return selectMysqlObject(
            conn,
            obj.database,
            obj.name,
            obj.kind,
          );
        }
        break;
      case 'sqlite':
        if (lastSelectedSqliteObject != null) {
          final obj = lastSelectedSqliteObject!;
          return selectSqliteObject(
            conn,
            obj.name,
            obj.kind,
          );
        }
        break;
      case 'mongodb':
        if (lastSelectedMongoDb != null) {
          return selectMongoDb(conn, lastSelectedMongoDb!);
        }
        break;
      case 'redis':
        if (lastSelectedRedisDb != null) {
          return selectRedisDb(conn, lastSelectedRedisDb!);
        }
        break;
      default:
        if (lastSelectedExtensionObject != null) {
          final obj = lastSelectedExtensionObject!;
          return selectExtensionObject(
            conn,
            obj.database,
            obj.name,
          );
        }
        break;
    }
    return this;
  }

  MainScreenWorkspaceState selectPostgresObject(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) {
    final pg = (
      database: database,
      schema: schema,
      name: name,
      kind: kind,
    );
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: pg,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: null,
      postgresSqlEditorContextToken: 0,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: null,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      lastSelectedPostgresObject: pg,
      lastSelectedMysqlObject: null,
      lastSelectedSqliteObject: null,
      lastSelectedExtensionObject: null,
      lastSelectedMongoDb: null,
      lastSelectedRedisDb: null,
      isReadOnly: isReadOnly,
    );
  }

  MainScreenWorkspaceState selectMysqlObject(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  ) {
    final my = (
      database: database,
      name: name,
      kind: kind,
    );
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: null,
      postgresSqlEditorContextToken: 0,
      selectedMysqlObject: my,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: null,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      lastSelectedPostgresObject: null,
      lastSelectedMysqlObject: my,
      lastSelectedSqliteObject: null,
      lastSelectedExtensionObject: null,
      lastSelectedMongoDb: null,
      lastSelectedRedisDb: null,
      isReadOnly: isReadOnly,
    );
  }

  MainScreenWorkspaceState selectSqliteObject(
    ConnectionRow connection,
    String name,
    SqliteObjectKind kind,
  ) {
    final sq = (
      name: name,
      kind: kind,
    );
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: null,
      postgresSqlEditorContextToken: 0,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: sq,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      lastSelectedPostgresObject: null,
      lastSelectedMysqlObject: null,
      lastSelectedSqliteObject: sq,
      lastSelectedExtensionObject: null,
      lastSelectedMongoDb: null,
      lastSelectedRedisDb: null,
      isReadOnly: isReadOnly,
    );
  }

  MainScreenWorkspaceState selectExtensionObject(
    ConnectionRow connection,
    String database,
    String name,
  ) {
    final ext = (
      database: database,
      name: name,
    );
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: null,
      postgresSqlEditorContextToken: 0,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: null,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      selectedExtensionObject: ext,
      lastSelectedPostgresObject: null,
      lastSelectedMysqlObject: null,
      lastSelectedSqliteObject: null,
      lastSelectedExtensionObject: ext,
      lastSelectedMongoDb: null,
      lastSelectedRedisDb: null,
      isReadOnly: isReadOnly,
    );
  }

  MainScreenWorkspaceState selectRedisDb(ConnectionRow connection, int db) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: db,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: null,
      postgresSqlEditorContextToken: 0,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: null,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      lastSelectedPostgresObject: null,
      lastSelectedMysqlObject: null,
      lastSelectedSqliteObject: null,
      lastSelectedExtensionObject: null,
      lastSelectedMongoDb: null,
      lastSelectedRedisDb: db,
      isReadOnly: isReadOnly,
    );
  }

  MainScreenWorkspaceState selectMongoDb(
      ConnectionRow connection, String database) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: database,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: null,
      postgresSqlEditorContextToken: 0,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: null,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      lastSelectedPostgresObject: null,
      lastSelectedMysqlObject: null,
      lastSelectedSqliteObject: null,
      lastSelectedExtensionObject: null,
      lastSelectedMongoDb: database,
      lastSelectedRedisDb: null,
      isReadOnly: isReadOnly,
    );
  }

  MainScreenWorkspaceState openPostgresSqlWorkspace(
    ConnectionRow connection, {
    String? seedDatabase,
    String? seedSchema,
    String? seedName,
    PostgresObjectKind? seedKind,
  }) {
    ({
      String database,
      String schema,
      String name,
      PostgresObjectKind kind
    })? seed;

    final explicit = seedDatabase != null &&
        seedSchema != null &&
        seedName != null &&
        seedName.isNotEmpty &&
        seedKind != null &&
        (seedKind == PostgresObjectKind.table ||
            seedKind == PostgresObjectKind.view ||
            seedKind == PostgresObjectKind.materializedView);

    if (explicit) {
      seed = (
        database: seedDatabase,
        schema: seedSchema,
        name: seedName,
        kind: seedKind,
      );
    } else {
      final sameConn = activeConnection?.id == connection.id;
      if (sameConn && selectedPostgresObject != null) {
        final o = selectedPostgresObject!;
        final k = o.kind;
        if (k == PostgresObjectKind.table ||
            k == PostgresObjectKind.view ||
            k == PostgresObjectKind.materializedView) {
          seed = o;
        }
      }
    }
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken + 1,
      postgresSqlEditorContext: seed,
      postgresSqlEditorContextToken:
          seed != null ? postgresSqlEditorContextToken + 1 : 0,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: null,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      lastSelectedPostgresObject: seed ?? lastSelectedPostgresObject,
      lastSelectedMysqlObject: lastSelectedMysqlObject,
      lastSelectedSqliteObject: lastSelectedSqliteObject,
      lastSelectedExtensionObject: lastSelectedExtensionObject,
      lastSelectedMongoDb: lastSelectedMongoDb,
      lastSelectedRedisDb: lastSelectedRedisDb,
      isReadOnly: isReadOnly,
    );
  }

  MainScreenWorkspaceState openMysqlSqlWorkspace(ConnectionRow connection) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: postgresSqlEditorContext,
      postgresSqlEditorContextToken: postgresSqlEditorContextToken,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken + 1,
      selectedSqliteObject: null,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken,
      lastSelectedPostgresObject: lastSelectedPostgresObject,
      lastSelectedMysqlObject: lastSelectedMysqlObject,
      lastSelectedSqliteObject: lastSelectedSqliteObject,
      lastSelectedExtensionObject: lastSelectedExtensionObject,
      lastSelectedMongoDb: lastSelectedMongoDb,
      lastSelectedRedisDb: lastSelectedRedisDb,
      isReadOnly: isReadOnly,
    );
  }

  MainScreenWorkspaceState openSqliteSqlWorkspace(ConnectionRow connection) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      postgresSqlEditorContext: postgresSqlEditorContext,
      postgresSqlEditorContextToken: postgresSqlEditorContextToken,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
      selectedSqliteObject: null,
      sqliteSqlTabRequestToken: sqliteSqlTabRequestToken + 1,
      lastSelectedPostgresObject: lastSelectedPostgresObject,
      lastSelectedMysqlObject: lastSelectedMysqlObject,
      lastSelectedSqliteObject: lastSelectedSqliteObject,
      lastSelectedExtensionObject: lastSelectedExtensionObject,
      lastSelectedMongoDb: lastSelectedMongoDb,
      lastSelectedRedisDb: lastSelectedRedisDb,
      isReadOnly: isReadOnly,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MainScreenWorkspaceState &&
        activeConnection?.id == other.activeConnection?.id &&
        activeRedisDb == other.activeRedisDb &&
        activeMongoDB == other.activeMongoDB &&
        _pgEquals(selectedPostgresObject, other.selectedPostgresObject) &&
        postgresSqlTabRequestToken == other.postgresSqlTabRequestToken &&
        _pgEquals(postgresSqlEditorContext, other.postgresSqlEditorContext) &&
        postgresSqlEditorContextToken == other.postgresSqlEditorContextToken &&
        _mysqlEquals(selectedMysqlObject, other.selectedMysqlObject) &&
        mysqlSqlTabRequestToken == other.mysqlSqlTabRequestToken &&
        _sqliteEquals(selectedSqliteObject, other.selectedSqliteObject) &&
        sqliteSqlTabRequestToken == other.sqliteSqlTabRequestToken &&
        _extensionEquals(
            selectedExtensionObject, other.selectedExtensionObject) &&
        _pgEquals(lastSelectedPostgresObject, other.lastSelectedPostgresObject) &&
        _mysqlEquals(lastSelectedMysqlObject, other.lastSelectedMysqlObject) &&
        _sqliteEquals(lastSelectedSqliteObject, other.lastSelectedSqliteObject) &&
        _extensionEquals(
            lastSelectedExtensionObject, other.lastSelectedExtensionObject) &&
        lastSelectedMongoDb == other.lastSelectedMongoDb &&
        lastSelectedRedisDb == other.lastSelectedRedisDb &&
        isReadOnly == other.isReadOnly;
  }

  @override
  int get hashCode => Object.hashAll([
        activeConnection?.id,
        activeRedisDb,
        activeMongoDB,
        selectedPostgresObject == null
            ? 0
            : Object.hash(
                selectedPostgresObject!.database,
                selectedPostgresObject!.schema,
                selectedPostgresObject!.name,
                selectedPostgresObject!.kind,
              ),
        postgresSqlTabRequestToken,
        postgresSqlEditorContext == null
            ? 0
            : Object.hash(
                postgresSqlEditorContext!.database,
                postgresSqlEditorContext!.schema,
                postgresSqlEditorContext!.name,
                postgresSqlEditorContext!.kind,
              ),
        postgresSqlEditorContextToken,
        selectedMysqlObject == null
            ? 0
            : Object.hash(
                selectedMysqlObject!.database,
                selectedMysqlObject!.name,
                selectedMysqlObject!.kind,
              ),
        mysqlSqlTabRequestToken,
        selectedSqliteObject == null
            ? 0
            : Object.hash(
                selectedSqliteObject!.name,
                selectedSqliteObject!.kind,
              ),
        sqliteSqlTabRequestToken,
        selectedExtensionObject == null
            ? 0
            : Object.hash(
                selectedExtensionObject!.database,
                selectedExtensionObject!.name,
              ),
        lastSelectedPostgresObject == null
            ? 0
            : Object.hash(
                lastSelectedPostgresObject!.database,
                lastSelectedPostgresObject!.schema,
                lastSelectedPostgresObject!.name,
                lastSelectedPostgresObject!.kind,
              ),
        lastSelectedMysqlObject == null
            ? 0
            : Object.hash(
                lastSelectedMysqlObject!.database,
                lastSelectedMysqlObject!.name,
                lastSelectedMysqlObject!.kind,
              ),
        lastSelectedSqliteObject == null
            ? 0
            : Object.hash(
                lastSelectedSqliteObject!.name,
                lastSelectedSqliteObject!.kind,
              ),
        lastSelectedExtensionObject == null
            ? 0
            : Object.hash(
                lastSelectedExtensionObject!.database,
                lastSelectedExtensionObject!.name,
              ),
        lastSelectedMongoDb,
        lastSelectedRedisDb,
        isReadOnly,
      ]);
}

bool _extensionEquals(
  ({String database, String name})? a,
  ({String database, String name})? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.database == b.database && a.name == b.name;
}

bool _pgEquals(
  ({String database, String schema, String name, PostgresObjectKind kind})? a,
  ({String database, String schema, String name, PostgresObjectKind kind})? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.database == b.database &&
      a.schema == b.schema &&
      a.name == b.name &&
      a.kind == b.kind;
}

bool _mysqlEquals(
  ({String database, String name, MysqlObjectKind kind})? a,
  ({String database, String name, MysqlObjectKind kind})? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.database == b.database && a.name == b.name && a.kind == b.kind;
}

bool _sqliteEquals(
  ({String name, SqliteObjectKind kind})? a,
  ({String name, SqliteObjectKind kind})? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.name == b.name && a.kind == b.kind;
}
