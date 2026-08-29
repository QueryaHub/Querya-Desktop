import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
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
import 'package:querya_desktop/features/macos/querya_platform_menu_bar.dart';
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/onboarding/welcome_tour_dialog.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
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
  bool _openingConnectionDialog = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
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
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    UnsandboxedLaunchConsentGate.instance.handler = null;
    _workspace.dispose();
    _isSidebarVisible.dispose();
    super.dispose();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final isMac = Platform.isMacOS;
    final isCmdOrCtrl = isMac
        ? (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)
        : HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    final physical = event.physicalKey;
    final logical = event.logicalKey;

    // 1. Execute SQL: F5, or (Ctrl/Cmd + Enter), or (Ctrl/Cmd + R)
    final isEnter = physical == PhysicalKeyboardKey.enter ||
        physical == PhysicalKeyboardKey.numpadEnter ||
        logical == LogicalKeyboardKey.enter ||
        logical == LogicalKeyboardKey.numpadEnter;
    final isF5 = physical == PhysicalKeyboardKey.f5 ||
        logical == LogicalKeyboardKey.f5;
    final isKeyR = physical == PhysicalKeyboardKey.keyR ||
        logical == LogicalKeyboardKey.keyR ||
        logical == const LogicalKeyboardKey(0x0000043a); // Russian 'к'

    if ((isCmdOrCtrl && isEnter) ||
        isF5 ||
        (isCmdOrCtrl && !isShift && !isAlt && isKeyR)) {
      if (SqlEditorCommandBridge.instance.canExecute) {
        SqlEditorCommandBridge.instance.invokeExecute();
        return true;
      }
    }

    // 2. Toggle Left Sidebar: Ctrl+B / Cmd+B (Physical B, Logical B, Russian 'и')
    final isKeyB = physical == PhysicalKeyboardKey.keyB ||
        logical == LogicalKeyboardKey.keyB ||
        logical == const LogicalKeyboardKey(0x00000438); // Russian 'и'
    if (isCmdOrCtrl && !isShift && !isAlt && isKeyB) {
      _splitKey.currentState?.toggleSidebar();
      return true;
    }

    // 3. New Connection / New Query Tab: (Physical N, Logical N, Russian 'т')
    final isKeyN = physical == PhysicalKeyboardKey.keyN ||
        logical == LogicalKeyboardKey.keyN ||
        logical == const LogicalKeyboardKey(0x00000442); // Russian 'т'
    if (isCmdOrCtrl && !isAlt && isKeyN) {
      if (isShift) {
        // Ctrl+Shift+N: New Query
        final ctx = FocusManager.instance.primaryFocus?.context ?? context;
        Actions.maybeInvoke(ctx, const NewSqlIntent());
      } else {
        // Ctrl+N: New Database Connection
        unawaited(_onNewDatabaseConnectionFromMenu());
      }
      return true;
    }

    // 4. Open SQL: Ctrl+O / Cmd+O (Physical O, Logical O, Russian 'щ')
    final isKeyO = physical == PhysicalKeyboardKey.keyO ||
        logical == LogicalKeyboardKey.keyO ||
        logical == const LogicalKeyboardKey(0x00000449); // Russian 'щ'
    if (isCmdOrCtrl && !isShift && !isAlt && isKeyO) {
      final ctx = FocusManager.instance.primaryFocus?.context ?? context;
      Actions.maybeInvoke(ctx, const OpenSqlIntent());
      return true;
    }

    // 5. Save SQL: Ctrl+S / Cmd+S (Physical S, Logical S, Russian 'ы')
    final isKeyS = physical == PhysicalKeyboardKey.keyS ||
        logical == LogicalKeyboardKey.keyS ||
        logical == const LogicalKeyboardKey(0x0000044b); // Russian 'ы'
    if (isCmdOrCtrl && !isShift && !isAlt && isKeyS) {
      final ctx = FocusManager.instance.primaryFocus?.context ?? context;
      Actions.maybeInvoke(ctx, const SaveSqlIntent());
      return true;
    }

    // 6. Tutorial & Welcome: F1 or Ctrl+Shift+H / Cmd+Shift+H (Physical H, Logical H, Russian 'р')
    final isF1 = physical == PhysicalKeyboardKey.f1 ||
        logical == LogicalKeyboardKey.f1;
    final isKeyH = physical == PhysicalKeyboardKey.keyH ||
        logical == LogicalKeyboardKey.keyH ||
        logical == const LogicalKeyboardKey(0x00000440); // Russian 'р'
    if (isF1 || (isCmdOrCtrl && isShift && isKeyH)) {
      _onOpenWelcomeTour();
      return true;
    }

    // 7. Home / Start Screen: Ctrl+Shift+0 / Cmd+Shift+0
    final isDigit0 = physical == PhysicalKeyboardKey.digit0 ||
        physical == PhysicalKeyboardKey.numpad0 ||
        logical == LogicalKeyboardKey.digit0 ||
        logical == LogicalKeyboardKey.numpad0;
    if (isCmdOrCtrl && isShift && isDigit0) {
      _onGoHome();
      return true;
    }

    return false;
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
    if (_openingConnectionDialog) return;
    _openingConnectionDialog = true;
    try {
      // Menu overlay context is torn down before the connection form opens.
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      final row = await promptCreateConnection(context, folderId: null);
      if (!mounted || row == null) return;
      await LocalDb.instance.addConnection(row);
      await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
    } finally {
      _openingConnectionDialog = false;
    }
  }

  Future<void> _onNewDatabaseConnectionFromUrl() async {
    if (_openingConnectionDialog) return;
    _openingConnectionDialog = true;
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      final row = await showNewConnectionUrlDialog(context);
      if (!mounted || row == null) return;
      await LocalDb.instance.addConnection(row);
      await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
    } finally {
      _openingConnectionDialog = false;
    }
  }

  Future<void> _openSqliteFromHero() async {
    final row = await showSqliteConnectionForm(context);
    if (!mounted || row == null) return;
    await LocalDb.instance.addConnection(row);
    await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
  }

  void _onGoHome() {
    _workspace.value = MainScreenWorkspaceState.empty;
  }

  void _onOpenWelcomeTour() {
    showWelcomeTourDialog(
      context,
      onLaunchDemo: _onLaunchDemoPlayground,
      onGoHome: _workspace.value.activeConnection != null ? _onGoHome : null,
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
        return FocusScope(
          autofocus: true,
          child: material.CallbackShortcuts(
            bindings: {
              // New Database Connection: Ctrl+N / Cmd+N
              const material.SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ): () => unawaited(_onNewDatabaseConnectionFromMenu()),
              const material.SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
              ): () => unawaited(_onNewDatabaseConnectionFromMenu()),

              // New Query Tab: Ctrl+Shift+N / Cmd+Shift+N
              const material.SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
                shift: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const NewSqlIntent());
              },
              const material.SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
                shift: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const NewSqlIntent());
              },

              // Open SQL File: Ctrl+O / Cmd+O
              const material.SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const OpenSqlIntent());
              },
              const material.SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const OpenSqlIntent());
              },

              // Save SQL File: Ctrl+S / Cmd+S
              const material.SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const SaveSqlIntent());
              },
              const material.SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const SaveSqlIntent());
              },

              // Toggle Left Sidebar: Ctrl+B / Cmd+B
              const material.SingleActivator(
                LogicalKeyboardKey.keyB,
                control: true,
              ): () => _splitKey.currentState?.toggleSidebar(),
              const material.SingleActivator(
                LogicalKeyboardKey.keyB,
                meta: true,
              ): () => _splitKey.currentState?.toggleSidebar(),

              // Welcome Tour & Tutorial: F1 / Cmd+Shift+H / Ctrl+Shift+H
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

              // Return to Start / Home Screen: Cmd+Shift+0 / Ctrl+Shift+0
              const material.SingleActivator(
                LogicalKeyboardKey.digit0,
                meta: true,
                shift: true,
              ): _onGoHome,
              const material.SingleActivator(
                LogicalKeyboardKey.digit0,
                control: true,
                shift: true,
              ): _onGoHome,
            },
            child: QueryaPlatformMenuBar(
              onNewConnection: () =>
                  unawaited(_onNewDatabaseConnectionFromMenu()),
              onNewQueryTab: () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const NewSqlIntent());
              },
              onOpenSqlScript: () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const OpenSqlIntent());
              },
              onSaveQuery: () {
                final ctx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(ctx, const SaveSqlIntent());
              },
              onExecuteQuery: () =>
                  SqlEditorCommandBridge.instance.invokeExecute(),
              onToggleSidebar: () => _splitKey.currentState?.toggleSidebar(),
              onOpenPreferences: () => showPreferencesDialog(context),
              onOpenWelcomeTour: () => _onOpenWelcomeTour(),
              onGoHome: _onGoHome,
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
                          onGoHome: _onGoHome,
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

  /// High-responsiveness critically damped spring for fluid sidebar toggling (~0.22s).
  static const SpringDescription _sidebarSpring = SpringDescription(
    mass: 1.0,
    stiffness: 580.0,
    damping: 48.0,
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
      cubicDuration: const Duration(milliseconds: 160),
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
        final currentW = _widthSpring.value.clamp(0.0, constraints.maxWidth);
        final isFullyCollapsed = currentW <= 0.001 && !_widthSpring.isAnimating;
        final progress = _lastExpandedWidth > 0
            ? (currentW / _lastExpandedWidth).clamp(0.0, 1.0)
            : 0.0;
        final currentHandleW =
            (progress * _resizeHandleWidth).clamp(0.0, _resizeHandleWidth);
        final handleOpacity = (progress * 5.0).clamp(0.0, 1.0);
        final contentOpacity = (progress * 2.2).clamp(0.0, 1.0);
        final parallaxOffset = (progress - 1.0) * 36.0;

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
            if (!isFullyCollapsed)
              SizedBox(
                width: currentHandleW,
                child: ClipRect(
                  child: OverflowBox(
                    minWidth: _resizeHandleWidth,
                    maxWidth: _resizeHandleWidth,
                    alignment: Alignment.center,
                    child: Opacity(
                      opacity: handleOpacity,
                      child: IgnorePointer(
                        ignoring: currentW <= 20.0 || !_sidebarVisible,
                        child: QueryaSplitHandle(
                          key: const Key('main_content_resize_handle'),
                          axis: Axis.horizontal,
                          semanticsLabel:
                              'Resize connections and workspace panes',
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
                            final useSprings =
                                QueryaSpring.springsEnabled(context);
                            _widthSpring.useSprings = useSprings;
                            if (_widthSpring.value < 100 && velocity < -50) {
                              _sidebarVisible = false;
                              widget.onSidebarVisibilityChanged?.call(false);
                              _widthSpring.animateTo(0.0, velocity: velocity);
                              unawaited(
                                  AppSettings.instance.setSidebarVisible(false));
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
                              unawaited(
                                  AppSettings.instance.setSidebarVisible(true));
                              _schedulePersistAfterSettle();
                            }
                          },
                        ),
                      ),
                    ),
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
                      lastSelectedPostgresObject: ws.lastSelectedPostgresObject,
                      lastSelectedMysqlObject: ws.lastSelectedMysqlObject,
                      lastSelectedSqliteObject: ws.lastSelectedSqliteObject,
                      lastSelectedExtensionObject:
                          ws.lastSelectedExtensionObject,
                      onNavigateHome: () {
                        widget.workspace.value =
                            widget.workspace.value.unselectActiveObject();
                      },
                      onRestoreLastSelectedObject: () {
                        widget.workspace.value =
                            widget.workspace.value.restoreLastSelectedObject();
                      },
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
  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_onWorkspaceChanged);
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_onWorkspaceChanged);
    super.dispose();
  }

  void _onWorkspaceChanged() {
    setState(() {});
  }

  @override
  material.Widget build(material.BuildContext context) {
    final ws = widget.workspace.value;
    return ConnectionsPanel(
      key: widget.connectionsPanelKey,
      selectedConnectionId: ws.activeConnection?.id,
      selectedPostgresObject: ws.selectedPostgresObject,
      selectedMysqlObject: ws.selectedMysqlObject,
      selectedSqliteObject: ws.selectedSqliteObject,
      selectedExtensionObject: ws.selectedExtensionObject,
      selectedRedisDb: ws.activeRedisDb,
      selectedMongoDb: ws.activeMongoDB,
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
