import 'dart:async';
import 'dart:math' as math;

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:querya_desktop/core/actions/sql_editor_global_actions.dart';
import 'package:querya_desktop/core/demo/demo_playground_service.dart';
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/layout/querya_split_handle.dart';
import 'package:querya_desktop/core/motion/querya_spring.dart';
import 'package:querya_desktop/core/motion/querya_spring_controller.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/extensions/sandbox/unsandboxed_launch_consent_gate.dart';
import 'package:querya_desktop/features/extensions/presentation/widgets/unsandboxed_driver_consent_dialog.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/connections/new_connection_url_dialog.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/features/connections/sqlite_connection_form.dart';
import 'package:querya_desktop/features/main_screen/connections_panel_width_persist.dart';
import 'package:querya_desktop/features/main_screen/querya_window_title_bar.dart';
import 'package:querya_desktop/features/onboarding/welcome_tour_dialog.dart';
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
  final GlobalKey<_MainContentSplitState> _splitKey =
      GlobalKey<_MainContentSplitState>();

  final ValueNotifier<MainScreenWorkspaceState> _workspace =
      ValueNotifier(MainScreenWorkspaceState.empty);
  final ValueNotifier<bool> _isSidebarVisible = ValueNotifier(true);

  @override
  void initState() {
    super.initState();
    UnsandboxedLaunchConsentGate.instance.handler = (details) {
      if (!mounted) return Future.value(false);
      return showUnsandboxedDriverConsentDialog(context, details);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final completed = await AppSettings.instance.getHasCompletedWelcomeTour();
      if (!completed && mounted) {
        final connections = await LocalDb.instance.getConnections();
        if (connections.isEmpty && mounted) {
          _onOpenWelcomeTour();
        }
      }
    });
  }

  @override
  void dispose() {
    UnsandboxedLaunchConsentGate.instance.handler = null;
    _workspace.dispose();
    _isSidebarVisible.dispose();
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

  void _onOpenWelcomeTour() {
    showWelcomeTourDialog(
      context,
      onLaunchDemo: _onLaunchDemoPlayground,
    );
  }

  Future<void> _onLaunchDemoPlayground() async {
    try {
      final demoConn = await DemoPlaygroundService.getOrCreateDemoConnection();
      if (!mounted) return;
      await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
      _workspace.value = _workspace.value.selectConnection(demoConn);
      _onSqliteOpenSqlWorkspace(demoConn);
    } catch (_) {}
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
            const material.SingleActivator(
              LogicalKeyboardKey.keyB,
              control: true,
            ): () => _splitKey.currentState?.toggleSidebar(),
            const material.SingleActivator(
              LogicalKeyboardKey.keyB,
              meta: true,
            ): () => _splitKey.currentState?.toggleSidebar(),
            const material.SingleActivator(
              LogicalKeyboardKey.f1,
            ): () => _onOpenWelcomeTour(),
            const material.SingleActivator(
              LogicalKeyboardKey.keyH,
              meta: true,
              shift: true,
            ): () => _onOpenWelcomeTour(),
            const material.SingleActivator(
              LogicalKeyboardKey.keyH,
              control: true,
              shift: true,
            ): () => _onOpenWelcomeTour(),
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
                    ValueListenableBuilder<bool>(
                      valueListenable: _isSidebarVisible,
                      builder: (context, isSidebarVisible, _) {
                        return QueryaWindowTitleBar(
                          onNewDatabaseConnection:
                              _onNewDatabaseConnectionFromMenu,
                          onNewDatabaseConnectionFromUrl:
                              _onNewDatabaseConnectionFromUrl,
                          activeConnection: workspace.activeConnection,
                          isReadOnly: workspace.isReadOnly,
                          isSidebarVisible: isSidebarVisible,
                          onToggleSidebar: () =>
                              _splitKey.currentState?.toggleSidebar(),
                          onOpenWelcomeTour: _onOpenWelcomeTour,
                          onReadOnlyChanged: () {
                            _workspace.value =
                                _workspace.value.toggleReadOnly();
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
                              _connectionsPanelKey.currentState
                                  ?.reconnect(active);
                            }
                          },
                          onDisconnect: () {
                            final active = workspace.activeConnection;
                            if (active != null) {
                              _connectionsPanelKey.currentState
                                  ?.disconnect(active);
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
                        );
                      },
                    ),
                    Divider(
                        height: 1,
                        color: wb.borderSubtle.withValues(alpha: 0.22)),
                    Expanded(
                      child: _MainContentSplit(
                        key: _splitKey,
                        connectionsPanelKey: _connectionsPanelKey,
                        workspace: _workspace,
                        onSidebarVisibilityChanged: (v) =>
                            _isSidebarVisible.value = v,
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
                        onRequestLaunchDemo: _onLaunchDemoPlayground,
                        onRequestOpenTour: _onOpenWelcomeTour,
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

/// Owns splitter width and collapsible spring motion.
class _MainContentSplit extends StatefulWidget {
  const _MainContentSplit({
    super.key,
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
    this.onRequestLaunchDemo,
    this.onRequestOpenTour,
    required this.onOpenConnection,
    this.onSidebarVisibilityChanged,
  });

  final GlobalKey<ConnectionsPanelState> connectionsPanelKey;
  final ValueNotifier<MainScreenWorkspaceState> workspace;
  final ValueChanged<bool>? onSidebarVisibilityChanged;
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
  final VoidCallback? onRequestLaunchDemo;
  final VoidCallback? onRequestOpenTour;
  final void Function(ConnectionRow) onOpenConnection;

  @override
  State<_MainContentSplit> createState() => _MainContentSplitState();
}

class _MainContentSplitState extends State<_MainContentSplit>
    with SingleTickerProviderStateMixin {
  static const double _minLeftWidth = 180;
  static const double _maxLeftWidth = 500;
  static const double _minWorkspaceWidth = 64;
  static const double _resizeHandleWidth = 6;

  /// High-responsiveness critically damped spring for fluid sidebar toggling (~0.25s).
  static const SpringDescription _sidebarSpring = SpringDescription(
    mass: 1.0,
    stiffness: 480.0,
    damping: 43.8,
  );

  late final QueryaSpringController _widthSpring;
  late final ConnectionsPanelWidthPersist _widthPersist;
  VoidCallback? _persistWhenSettled;
  double _lastMaxWidth = 1200;
  double _lastExpandedWidth = kDefaultConnectionsPanelWidth;
  bool _sidebarVisible = true;

  @override
  void initState() {
    super.initState();
    _widthPersist = ConnectionsPanelWidthPersist(
      write: AppSettings.instance.setConnectionsPanelWidth,
    );
    _widthSpring = QueryaSpringController(
      vsync: this,
      value: kDefaultConnectionsPanelWidth,
      spring: _sidebarSpring,
      cubicDuration: const Duration(milliseconds: 170),
      cubicCurve: Curves.easeOutCubic,
    );
    _widthSpring.addListener(_onWidthSpringChanged);
    unawaited(_restoreState());
  }

  Future<void> _restoreState() async {
    final width = await AppSettings.instance.getConnectionsPanelWidth();
    final visible = await AppSettings.instance.getSidebarVisible();
    if (!mounted) return;
    final clamped = _clampLeftWidth(width, _lastMaxWidth);
    _lastExpandedWidth = clamped;
    _sidebarVisible = visible;
    widget.onSidebarVisibilityChanged?.call(visible);
    final targetW = visible ? clamped : 0.0;
    _widthSpring.jumpTo(targetW);
  }

  void toggleSidebar({bool? visible}) {
    final target = visible ?? !_sidebarVisible;
    _sidebarVisible = target;
    widget.onSidebarVisibilityChanged?.call(target);
    _widthSpring.useSprings = QueryaSpring.springsEnabled(context);
    final targetWidth = target ? _lastExpandedWidth : 0.0;
    _widthSpring.animateTo(targetWidth);
    unawaited(AppSettings.instance.setSidebarVisible(target));
  }

  void _onWidthSpringChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _schedulePersistAfterSettle() {
    _widthPersist.markDirty();
    final pending = _persistWhenSettled;
    if (pending != null) {
      _widthSpring.removeListener(pending);
    }
    void listener() {
      if (_widthSpring.isAnimating) return;
      _widthSpring.removeListener(listener);
      _persistWhenSettled = null;
      if (_sidebarVisible) {
        unawaited(_widthPersist.persist(_lastExpandedWidth));
      }
    }

    _persistWhenSettled = listener;
    if (_widthSpring.isAnimating) {
      _widthSpring.addListener(listener);
    } else {
      listener();
    }
  }

  @override
  void dispose() {
    final pending = _persistWhenSettled;
    if (pending != null) {
      _widthSpring.removeListener(pending);
      _persistWhenSettled = null;
    }
    if (_sidebarVisible) {
      _widthPersist.disposeFlush(_lastExpandedWidth);
    }
    _widthSpring.removeListener(_onWidthSpringChanged);
    _widthSpring.dispose();
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
        _lastMaxWidth = constraints.maxWidth;
        final currentW = _widthSpring.value;
        final isFullyCollapsed = currentW <= 0.5 && !_widthSpring.isAnimating;
        final handleOpacity = (currentW / 40.0).clamp(0.0, 1.0);
        final parallaxOffset = (currentW - _lastExpandedWidth) * 0.28;
        final contentOpacity = _lastExpandedWidth > 0
            ? (currentW / (_lastExpandedWidth * 0.45)).clamp(0.0, 1.0)
            : 1.0;

        return Row(
          children: [
            if (!isFullyCollapsed)
              ClipRect(
                child: SizedBox(
                  width: currentW,
                  child: OverflowBox(
                    minWidth: _lastExpandedWidth,
                    maxWidth: _lastExpandedWidth,
                    alignment: Alignment.topLeft,
                    child: Transform.translate(
                      offset: Offset(parallaxOffset, 0),
                      child: Opacity(
                        opacity: contentOpacity,
                        child: material.RepaintBoundary(
                          child: _ConnectionsPanelSlot(
                            connectionsPanelKey: widget.connectionsPanelKey,
                            workspace: widget.workspace,
                            onConnectionSelected: widget.onConnectionSelected,
                            onRedisDatabaseSelected:
                                widget.onRedisDatabaseSelected,
                            onMongoDBDatabaseSelected:
                                widget.onMongoDBDatabaseSelected,
                            onPostgresObjectSelected:
                                widget.onPostgresObjectSelected,
                            onPostgresOpenSqlWorkspace:
                                widget.onPostgresOpenSqlWorkspace,
                            onMysqlObjectSelected: widget.onMysqlObjectSelected,
                            onMysqlOpenSqlWorkspace:
                                widget.onMysqlOpenSqlWorkspace,
                            onSqliteObjectSelected:
                                widget.onSqliteObjectSelected,
                            onSqliteOpenSqlWorkspace:
                                widget.onSqliteOpenSqlWorkspace,
                            onExtensionObjectSelected:
                                widget.onExtensionObjectSelected,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (!isFullyCollapsed || _widthSpring.isAnimating)
              Opacity(
                opacity: handleOpacity,
                child: IgnorePointer(
                  ignoring: currentW <= 20.0,
                  child: QueryaSplitHandle(
                    key: const Key('main_content_resize_handle'),
                    axis: Axis.horizontal,
                    semanticsLabel: 'Resize connections and workspace panes',
                    onDragDelta: (dx) {
                      final ml = constraints.maxWidth -
                          _resizeHandleWidth -
                          _minWorkspaceWidth;
                      if (ml <= 0) return;
                      final nextW = _clampLeftWidth(
                        _widthSpring.value + dx,
                        constraints.maxWidth,
                      );
                      _lastExpandedWidth = nextW;
                      _widthSpring.jumpTo(nextW);
                    },
                    onDiscreteResize: () => _widthPersist
                        .onDiscreteResize(() => _lastExpandedWidth),
                    onDragEnd: (details) {
                      _widthPersist.cancelDiscreteTimer();
                      final velocity = details.primaryVelocity ??
                          details.velocity.pixelsPerSecond.dx;
                      final useSprings = QueryaSpring.springsEnabled(context);
                      _widthSpring.useSprings = useSprings;
                      if (_widthSpring.value < 100 && velocity < -50) {
                        _sidebarVisible = false;
                        widget.onSidebarVisibilityChanged?.call(false);
                        _widthSpring.animateTo(0.0, velocity: velocity);
                        unawaited(AppSettings.instance.setSidebarVisible(false));
                      } else {
                        _sidebarVisible = true;
                        widget.onSidebarVisibilityChanged?.call(true);
                        _lastExpandedWidth = _clampLeftWidth(
                          _widthSpring.value,
                          constraints.maxWidth,
                        );
                        _widthSpring.animateTo(
                          _lastExpandedWidth,
                          velocity: velocity,
                        );
                        unawaited(AppSettings.instance.setSidebarVisible(true));
                        _schedulePersistAfterSettle();
                      }
                    },
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
                      onRequestLaunchDemo: widget.onRequestLaunchDemo,
                      onRequestOpenTour: widget.onRequestOpenTour,
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
