import 'dart:async';
import 'dart:math' as math;

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:querya_desktop/core/actions/sql_editor_global_actions.dart';
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/layout/querya_split_handle.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/connections/new_connection_url_dialog.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/features/connections/sqlite_connection_form.dart';
import 'package:querya_desktop/features/main_screen/querya_window_title_bar.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'main_screen_workspace_state.dart';
import 'workspace_panel.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<ConnectionsPanelState> _connectionsPanelKey =
      GlobalKey<ConnectionsPanelState>();

  final ValueNotifier<MainScreenWorkspaceState> _workspace =
      ValueNotifier(MainScreenWorkspaceState.empty);

  @override
  void dispose() {
    _workspace.dispose();
    super.dispose();
  }

  void _onConnectionSelected(ConnectionRow connection) {
    _workspace.value = _workspace.value.selectConnection(connection);
    final id = connection.id;
    if (id != null) {
      unawaited(AppSettings.instance.recordRecentConnection(id));
    }
  }

  void _onPostgresObjectSelected(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) {
    _workspace.value = _workspace.value.selectPostgresObject(
      connection,
      database,
      schema,
      name,
      kind,
    );
  }

  void _onMysqlObjectSelected(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  ) {
    _workspace.value = _workspace.value.selectMysqlObject(
      connection,
      database,
      name,
      kind,
    );
  }

  void _onRedisDatabaseSelected(ConnectionRow connection, int database) {
    _workspace.value = _workspace.value.selectRedisDb(connection, database);
  }

  void _onMongoDBDatabaseSelected(ConnectionRow connection, String database) {
    _workspace.value = _workspace.value.selectMongoDb(connection, database);
  }

  void _onPostgresOpenSqlWorkspace(
    ConnectionRow connection, {
    String? database,
    String? schema,
    String? name,
    PostgresObjectKind? kind,
  }) {
    _workspace.value = _workspace.value.openPostgresSqlWorkspace(
      connection,
      seedDatabase: database,
      seedSchema: schema,
      seedName: name,
      seedKind: kind,
    );
  }

  void _onMysqlOpenSqlWorkspace(ConnectionRow connection) {
    _workspace.value = _workspace.value.openMysqlSqlWorkspace(connection);
  }

  void _onSqliteObjectSelected(
    ConnectionRow connection,
    String name,
    SqliteObjectKind kind,
  ) {
    _workspace.value = _workspace.value.selectSqliteObject(
      connection,
      name,
      kind,
    );
  }

  void _onSqliteOpenSqlWorkspace(ConnectionRow connection) {
    _workspace.value = _workspace.value.openSqliteSqlWorkspace(connection);
  }

  void _onExtensionObjectSelected(
    ConnectionRow connection,
    String database,
    String name,
  ) {
    _workspace.value = _workspace.value.selectExtensionObject(
      connection,
      database,
      name,
    );
  }

  void _openSqlWorkspaceForConnection(ConnectionRow connection) {
    switch (connection.type) {
      case 'postgresql':
        _onPostgresOpenSqlWorkspace(connection);
      case 'mysql':
        _onMysqlOpenSqlWorkspace(connection);
      case 'sqlite':
        _onSqliteOpenSqlWorkspace(connection);
      default:
        if (ExtensionDriverCatalog.isExtensionDriverConnection(connection)) {
          _workspace.value = _workspace.value.selectConnection(connection);
        }
    }
  }

  Future<void> _openNewConnectionFromHero() async {
    final row = await promptCreateConnection(context);
    if (!mounted || row == null) return;
    await LocalDb.instance.addConnection(row);
    await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
  }

  Future<void> _onNewDatabaseConnectionFromMenu() async {
    // Menu overlay context is torn down before the connection form opens.
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    final row = await promptCreateConnection(context, folderId: null);
    if (!mounted || row == null) return;
    await LocalDb.instance.addConnection(row);
    await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
  }

  Future<void> _onNewDatabaseConnectionFromUrl() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    final row = await showNewConnectionUrlDialog(context);
    if (!mounted || row == null) return;
    await LocalDb.instance.addConnection(row);
    await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
  }

  Future<void> _openSqliteFromHero() async {
    final row = await showSqliteConnectionForm(context);
    if (!mounted || row == null) return;
    await LocalDb.instance.addConnection(row);
    await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    return ValueListenableBuilder<MainScreenWorkspaceState>(
      valueListenable: _workspace,
      builder: (context, workspace, _) {
        return material.CallbackShortcuts(
          bindings: {
            const material.SingleActivator(
              LogicalKeyboardKey.keyN,
              control: true,
              shift: true,
            ): () => unawaited(_onNewDatabaseConnectionFromMenu()),
          },
          child: SqlEditorGlobalActions(
            activeConnection: workspace.activeConnection,
            onOpenSqlWorkspace: _openSqlWorkspaceForConnection,
            child: material.Scaffold(
              backgroundColor: wb.canvas,
              body: WindowBorder(
                color: wb.borderSubtle.withValues(alpha: 0.35),
                width: 1,
                child: Column(
                  children: [
                    QueryaWindowTitleBar(
                      onNewDatabaseConnection: _onNewDatabaseConnectionFromMenu,
                      onNewDatabaseConnectionFromUrl:
                          _onNewDatabaseConnectionFromUrl,
                      activeConnection: workspace.activeConnection,
                      isReadOnly: workspace.isReadOnly,
                      onReadOnlyChanged: () {
                        _workspace.value = _workspace.value.toggleReadOnly();
                      },
                      onConnect: () {
                        final active = workspace.activeConnection;
                        if (active != null && active.id != null) {
                          _connectionsPanelKey.currentState
                              ?.connect(active.id!);
                        }
                      },
                      onReconnect: () {
                        final active = workspace.activeConnection;
                        if (active != null) {
                          _connectionsPanelKey.currentState?.reconnect(active);
                        }
                      },
                      onDisconnect: () {
                        final active = workspace.activeConnection;
                        if (active != null) {
                          _connectionsPanelKey.currentState?.disconnect(active);
                        }
                      },
                      onDisconnectAll: () {
                        _connectionsPanelKey.currentState?.disconnectAll();
                      },
                      onDisconnectOthers: () {
                        final active = workspace.activeConnection;
                        if (active != null) {
                          _connectionsPanelKey.currentState
                              ?.disconnectOthers(active);
                        }
                      },
                    ),
                    Divider(
                        height: 1,
                        color: wb.borderSubtle.withValues(alpha: 0.22)),
                    Expanded(
                      child: _MainContentSplit(
                        connectionsPanelKey: _connectionsPanelKey,
                        workspace: _workspace,
                        onConnectionSelected: _onConnectionSelected,
                        onPostgresObjectSelected: _onPostgresObjectSelected,
                        onMysqlObjectSelected: _onMysqlObjectSelected,
                        onSqliteObjectSelected: _onSqliteObjectSelected,
                        onExtensionObjectSelected: _onExtensionObjectSelected,
                        onRedisDatabaseSelected: _onRedisDatabaseSelected,
                        onMongoDBDatabaseSelected: _onMongoDBDatabaseSelected,
                        onPostgresOpenSqlWorkspace: _onPostgresOpenSqlWorkspace,
                        onMysqlOpenSqlWorkspace: _onMysqlOpenSqlWorkspace,
                        onSqliteOpenSqlWorkspace: _onSqliteOpenSqlWorkspace,
                        onRequestNewConnection: _openNewConnectionFromHero,
                        onRequestNewConnectionFromUrl:
                            _onNewDatabaseConnectionFromUrl,
                        onRequestOpenSqlite: _openSqliteFromHero,
                        onOpenConnection: _onConnectionSelected,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Owns splitter width so resizing does not rebuild [MainScreen] or title bar.
class _MainContentSplit extends StatefulWidget {
  const _MainContentSplit({
    required this.connectionsPanelKey,
    required this.workspace,
    required this.onConnectionSelected,
    required this.onPostgresObjectSelected,
    required this.onMysqlObjectSelected,
    required this.onSqliteObjectSelected,
    required this.onExtensionObjectSelected,
    required this.onRedisDatabaseSelected,
    required this.onMongoDBDatabaseSelected,
    required this.onPostgresOpenSqlWorkspace,
    required this.onMysqlOpenSqlWorkspace,
    required this.onSqliteOpenSqlWorkspace,
    required this.onRequestNewConnection,
    required this.onRequestNewConnectionFromUrl,
    required this.onRequestOpenSqlite,
    required this.onOpenConnection,
  });

  final GlobalKey<ConnectionsPanelState> connectionsPanelKey;
  final ValueNotifier<MainScreenWorkspaceState> workspace;
  final void Function(ConnectionRow) onConnectionSelected;
  final void Function(
    ConnectionRow,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) onPostgresObjectSelected;
  final void Function(
    ConnectionRow,
    String database,
    String name,
    MysqlObjectKind kind,
  ) onMysqlObjectSelected;
  final void Function(
    ConnectionRow,
    String name,
    SqliteObjectKind kind,
  ) onSqliteObjectSelected;
  final void Function(
    ConnectionRow,
    String database,
    String name,
  ) onExtensionObjectSelected;
  final void Function(ConnectionRow, int) onRedisDatabaseSelected;
  final void Function(ConnectionRow, String) onMongoDBDatabaseSelected;
  final OnPostgresOpenSqlWorkspace onPostgresOpenSqlWorkspace;
  final void Function(ConnectionRow) onMysqlOpenSqlWorkspace;
  final void Function(ConnectionRow) onSqliteOpenSqlWorkspace;
  final VoidCallback onRequestNewConnection;
  final VoidCallback onRequestNewConnectionFromUrl;
  final VoidCallback onRequestOpenSqlite;
  final void Function(ConnectionRow) onOpenConnection;

  @override
  State<_MainContentSplit> createState() => _MainContentSplitState();
}

class _MainContentSplitState extends State<_MainContentSplit> {
  static const double _minLeftWidth = 180;
  static const double _maxLeftWidth = 500;
  static const double _minWorkspaceWidth = 64;
  static const double _resizeHandleWidth = 6;
  final ValueNotifier<double> _leftPanelWidth =
      ValueNotifier(kDefaultConnectionsPanelWidth);

  @override
  void initState() {
    super.initState();
    unawaited(_restoreConnectionsPanelWidth());
  }

  Future<void> _restoreConnectionsPanelWidth() async {
    final width = await AppSettings.instance.getConnectionsPanelWidth();
    if (!mounted) return;
    _leftPanelWidth.value = width;
  }

  @override
  void dispose() {
    _leftPanelWidth.dispose();
    super.dispose();
  }

  double _clampLeftWidth(double raw, double maxWidth) {
    final maxLeft = maxWidth - _resizeHandleWidth - _minWorkspaceWidth;
    if (maxLeft <= 0) return 0;
    if (maxLeft < _minLeftWidth) return raw.clamp(0, maxLeft);
    return raw.clamp(_minLeftWidth, math.min(_maxLeftWidth, maxLeft));
  }

  @override
  material.Widget build(material.BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _leftPanelWidth,
              builder: (context, rawWidth, connectionsPanel) {
                final leftW = _clampLeftWidth(rawWidth, constraints.maxWidth);
                return SizedBox(width: leftW, child: connectionsPanel);
              },
              child: material.RepaintBoundary(
                child: _ConnectionsPanelSlot(
                  connectionsPanelKey: widget.connectionsPanelKey,
                  workspace: widget.workspace,
                  onConnectionSelected: widget.onConnectionSelected,
                  onRedisDatabaseSelected: widget.onRedisDatabaseSelected,
                  onMongoDBDatabaseSelected: widget.onMongoDBDatabaseSelected,
                  onPostgresObjectSelected: widget.onPostgresObjectSelected,
                  onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                  onMysqlObjectSelected: widget.onMysqlObjectSelected,
                  onMysqlOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
                  onSqliteObjectSelected: widget.onSqliteObjectSelected,
                  onSqliteOpenSqlWorkspace: widget.onSqliteOpenSqlWorkspace,
                  onExtensionObjectSelected: widget.onExtensionObjectSelected,
                ),
              ),
            ),
            QueryaSplitHandle(
              key: const Key('main_content_resize_handle'),
              axis: Axis.horizontal,
              semanticsLabel: 'Resize connections and workspace panes',
              onDragDelta: (dx) {
                final ml = constraints.maxWidth -
                    _resizeHandleWidth -
                    _minWorkspaceWidth;
                if (ml <= 0) return;
                _leftPanelWidth.value = _clampLeftWidth(
                  _leftPanelWidth.value + dx,
                  constraints.maxWidth,
                );
              },
              onDragEnd: () => unawaited(
                AppSettings.instance.setConnectionsPanelWidth(
                  _leftPanelWidth.value,
                ),
              ),
            ),
            Expanded(
              child: material.RepaintBoundary(
                child: ValueListenableBuilder<MainScreenWorkspaceState>(
                  valueListenable: widget.workspace,
                  builder: (context, ws, _) {
                    return WorkspacePanel(
                      activeConnection: ws.activeConnection,
                      selectedRedisDb: ws.activeRedisDb,
                      selectedMongoDb: ws.activeMongoDB,
                      selectedPostgresObject: ws.selectedPostgresObject,
                      postgresSqlTabRequestToken: ws.postgresSqlTabRequestToken,
                      postgresSqlEditorContext: ws.postgresSqlEditorContext,
                      postgresSqlEditorContextToken:
                          ws.postgresSqlEditorContextToken,
                      selectedMysqlObject: ws.selectedMysqlObject,
                      mysqlSqlTabRequestToken: ws.mysqlSqlTabRequestToken,
                      selectedSqliteObject: ws.selectedSqliteObject,
                      sqliteSqlTabRequestToken: ws.sqliteSqlTabRequestToken,
                      selectedExtensionObject: ws.selectedExtensionObject,
                      isReadOnly: ws.isReadOnly,
                      onRequestNewConnection: widget.onRequestNewConnection,
                      onRequestNewConnectionFromUrl:
                          widget.onRequestNewConnectionFromUrl,
                      onRequestOpenSqlite: widget.onRequestOpenSqlite,
                      onOpenConnection: widget.onOpenConnection,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Rebuilds [ConnectionsPanel] only when the selected connection id changes.
class _ConnectionsPanelSlot extends StatefulWidget {
  const _ConnectionsPanelSlot({
    required this.connectionsPanelKey,
    required this.workspace,
    required this.onConnectionSelected,
    required this.onPostgresObjectSelected,
    required this.onMysqlObjectSelected,
    required this.onSqliteObjectSelected,
    required this.onRedisDatabaseSelected,
    required this.onMongoDBDatabaseSelected,
    required this.onPostgresOpenSqlWorkspace,
    required this.onMysqlOpenSqlWorkspace,
    required this.onSqliteOpenSqlWorkspace,
    required this.onExtensionObjectSelected,
  });

  final GlobalKey<ConnectionsPanelState> connectionsPanelKey;
  final ValueNotifier<MainScreenWorkspaceState> workspace;
  final void Function(ConnectionRow) onConnectionSelected;
  final void Function(
    ConnectionRow,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) onPostgresObjectSelected;
  final void Function(
    ConnectionRow,
    String database,
    String name,
    MysqlObjectKind kind,
  ) onMysqlObjectSelected;
  final void Function(
    ConnectionRow,
    String name,
    SqliteObjectKind kind,
  ) onSqliteObjectSelected;
  final void Function(ConnectionRow, int) onRedisDatabaseSelected;
  final void Function(ConnectionRow, String) onMongoDBDatabaseSelected;
  final OnPostgresOpenSqlWorkspace onPostgresOpenSqlWorkspace;
  final void Function(ConnectionRow) onMysqlOpenSqlWorkspace;
  final void Function(ConnectionRow) onSqliteOpenSqlWorkspace;
  final void Function(
    ConnectionRow,
    String database,
    String name,
  ) onExtensionObjectSelected;

  @override
  State<_ConnectionsPanelSlot> createState() => _ConnectionsPanelSlotState();
}

class _ConnectionsPanelSlotState extends State<_ConnectionsPanelSlot> {
  int? _selectedConnectionId;

  @override
  void initState() {
    super.initState();
    _selectedConnectionId = widget.workspace.value.activeConnection?.id;
    widget.workspace.addListener(_onWorkspaceChanged);
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_onWorkspaceChanged);
    super.dispose();
  }

  void _onWorkspaceChanged() {
    final next = widget.workspace.value.activeConnection?.id;
    if (next != _selectedConnectionId) {
      setState(() => _selectedConnectionId = next);
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    return ConnectionsPanel(
      key: widget.connectionsPanelKey,
      selectedConnectionId: _selectedConnectionId,
      onConnectionSelected: widget.onConnectionSelected,
      onRedisDatabaseSelected: widget.onRedisDatabaseSelected,
      onMongoDBDatabaseSelected: widget.onMongoDBDatabaseSelected,
      onPostgresObjectSelected: widget.onPostgresObjectSelected,
      onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
      onMysqlObjectSelected: widget.onMysqlObjectSelected,
      onMysqlOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
      onSqliteObjectSelected: widget.onSqliteObjectSelected,
      onSqliteOpenSqlWorkspace: widget.onSqliteOpenSqlWorkspace,
      onExtensionObjectSelected: widget.onExtensionObjectSelected,
    );
  }
}
