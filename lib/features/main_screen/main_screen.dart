import 'dart:async';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/features/command_palette/command_palette_dialog.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/actions/sql_editor_global_actions.dart';
import 'package:querya_desktop/core/demo/demo_playground_service.dart';
import 'package:querya_desktop/core/platform/file_launch_service.dart';
import 'package:querya_desktop/core/security/safe_mode.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/extensions/sandbox/unsandboxed_launch_consent_gate.dart';
import 'package:querya_desktop/features/extensions/presentation/widgets/unsandboxed_driver_consent_dialog.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/connections/new_connection_url_dialog.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/features/connections/sqlite_connection_form.dart';
import 'package:querya_desktop/core/ui/querya_shell_status.dart';
import 'package:querya_desktop/features/main_screen/querya_status_bar.dart';
import 'package:querya_desktop/features/main_screen/safe_mode_unlock_dialog.dart';
import 'package:querya_desktop/features/main_screen/querya_window_title_bar.dart';
import 'package:querya_desktop/features/macos/querya_platform_menu_bar.dart';
import 'package:querya_desktop/features/onboarding/welcome_tour_dialog.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'main_screen_workspace_state.dart';
import 'main_content_split.dart';
import 'main_screen_navigator.dart';
import 'main_screen_shortcuts.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<ConnectionsPanelState> _connectionsPanelKey =
      GlobalKey<ConnectionsPanelState>();
  final GlobalKey<MainContentSplitState> _splitKey =
      GlobalKey<MainContentSplitState>();

  final ValueNotifier<MainScreenWorkspaceState> _workspace =
      ValueNotifier(MainScreenWorkspaceState.empty);
  final ValueNotifier<bool> _isSidebarVisible = ValueNotifier(true);
  bool _openingConnectionDialog = false;
  late final MainScreenNavigator _nav = MainScreenNavigator(
    workspace: _workspace,
    context: () => context,
    mounted: () => mounted,
    onPendingMongoCollectionChanged: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    UnsandboxedLaunchConsentGate.instance.handler = (details) {
      if (!mounted) return Future.value(false);
      return showUnsandboxedDriverConsentDialog(context, details);
    };

    // Files Finder opens while the window is up (#1589).
    FileLaunchService.instance.pendingRevision.addListener(_onFilesQueued);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final completed = await AppSettings.instance.getHasCompletedWelcomeTour();
      if (!completed && mounted) {
        final connections = await LocalDb.instance.getConnections();
        if (connections.isEmpty &&
            mounted &&
            !FileLaunchService.instance.hasPendingTargets) {
          _onOpenWelcomeTour();
        }
      }
      if (mounted) {
        await _handlePendingFileLaunch();
      }
    });
  }

  void _onFilesQueued() {
    if (mounted) unawaited(_handlePendingFileLaunch());
  }

  @override
  void dispose() {
    FileLaunchService.instance.pendingRevision.removeListener(_onFilesQueued);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    UnsandboxedLaunchConsentGate.instance.handler = null;
    _safeModeRelockTimer?.cancel();
    _workspace.dispose();
    _isSidebarVisible.dispose();
    super.dispose();
  }

  Timer? _safeModeRelockTimer;

  /// Toggles the read-only lock. Turning it off for a Production connection
  /// (Safe Mode) needs a typed confirmation and re-locks after
  /// [kSafeModeUnlockDuration].
  Future<void> _toggleReadOnly() async {
    final ws = _workspace.value;
    final connection = ws.activeConnection;
    if (connection == null) return;

    if (ws.isReadOnly &&
        safeModeRequiresConfirmation(connection.environment)) {
      final confirmed = await showSafeModeUnlockDialog(
        context: context,
        connectionName: connection.name,
      );
      if (!confirmed || !mounted) return;
      final current = _workspace.value;
      if (current.activeConnection?.id != connection.id || !current.isReadOnly) {
        return;
      }
      _workspace.value = current.toggleReadOnly();
      _safeModeRelockTimer?.cancel();
      _safeModeRelockTimer = Timer(kSafeModeUnlockDuration, () {
        if (!mounted) return;
        final latest = _workspace.value;
        if (latest.activeConnection?.id == connection.id &&
            !latest.isReadOnly) {
          _workspace.value = latest.toggleReadOnly();
          showAppToast(
            context: context,
            message: '${connection.name} is read-only again',
          );
        }
      });
      return;
    }

    _safeModeRelockTimer?.cancel();
    _workspace.value = ws.toggleReadOnly();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final keyboard = HardwareKeyboard.instance;
    final shortcut = MainScreenShortcuts.resolve(
      event,
      cmdOrCtrl: Platform.isMacOS
          ? (keyboard.isMetaPressed || keyboard.isControlPressed)
          : keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
    );
    if (shortcut == null) return false;

    BuildContext focused() =>
        FocusManager.instance.primaryFocus?.context ?? context;
    // An intent the focused editor handles, else the bridge to the open one.
    void intentOr(Intent intent, void Function() fallback) {
      if (Actions.maybeInvoke(focused(), intent) == null) fallback();
    }

    final bridge = SqlEditorCommandBridge.instance;
    switch (shortcut) {
      case MainShortcut.runScript:
        if (!bridge.canExecute) return false;
        bridge.invokeExecute();
      case MainShortcut.runStatement:
        if (!bridge.canExecute) return false;
        bridge.invokeExecuteStatement();
      case MainShortcut.preferences:
        showPreferencesDialog(context);
      case MainShortcut.toggleSidebar:
        _splitKey.currentState?.toggleSidebar();
      case MainShortcut.commandPalette:
        unawaited(showCommandPalette(focused()));
      case MainShortcut.quickSwitcher:
        _nav.openQuickSwitcher();
      case MainShortcut.newConnection:
        unawaited(_onNewDatabaseConnectionFromMenu());
      case MainShortcut.newQuery:
        Actions.maybeInvoke(focused(), const NewSqlIntent());
      case MainShortcut.newQueryTab:
        intentOr(const NewSqlIntent(), bridge.invokeNew);
      case MainShortcut.closeQueryTab:
        intentOr(const CloseSqlTabIntent(), bridge.invokeCloseTab);
      case MainShortcut.nextQueryTab:
        intentOr(const NextSqlTabIntent(), bridge.invokeNextTab);
      case MainShortcut.prevQueryTab:
        intentOr(const PrevSqlTabIntent(), bridge.invokePrevTab);
      case MainShortcut.openSql:
        Actions.maybeInvoke(focused(), const OpenSqlIntent());
      case MainShortcut.saveSql:
        Actions.maybeInvoke(focused(), const SaveSqlIntent());
      case MainShortcut.welcomeTour:
        _onOpenWelcomeTour();
      case MainShortcut.goHome:
        _nav.onGoHome();
    }
    return true;
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

  void _onOpenWelcomeTour() {
    showWelcomeTourDialog(
      context,
      onLaunchDemo: _onLaunchDemoPlayground,
      onGoHome: _workspace.value.activeConnection != null ? _nav.onGoHome : null,
    );
  }

  Future<void> _onLaunchDemoPlayground() async {
    try {
      final demoConn = await DemoPlaygroundService.getOrCreateDemoConnection();
      if (!mounted) return;
      await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
      _workspace.value = _workspace.value.selectConnection(demoConn);
      _nav.onSqliteOpenSqlWorkspace(demoConn);
    } catch (_) {}
  }

  Future<void> _handlePendingFileLaunch() async {
    final targets = FileLaunchService.instance.consumePendingTargets();
    if (targets.isEmpty || !mounted) return;

    for (final target in targets) {
      if (!mounted) return;
      try {
        if (target.kind == FileLaunchKind.sqlite) {
          final conn = await FileLaunchService.instance
              .resolveOrRegisterSqliteConnection(target);
          if (!mounted) return;
          await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
          _workspace.value = _workspace.value.selectConnection(conn);
          _nav.onSqliteOpenSqlWorkspace(conn);
        } else if (target.kind == FileLaunchKind.sql) {
          final sql = await FileLaunchService.instance.readSqlContent(target);
          if (!mounted) return;

          var conn = _workspace.value.activeConnection;
          if (conn == null) {
            final connections = await LocalDb.instance.getConnections();
            if (connections.isNotEmpty) {
              conn = connections.first;
            } else {
              final scratchRow = ConnectionRow(
                name: 'Local Scratch (${target.fileName})',
                type: 'sqlite',
                host: '',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              );
              final id = await LocalDb.instance.addConnection(scratchRow);
              conn = scratchRow.copyWith(id: id);
              await _connectionsPanelKey.currentState?.reloadConnectionsFromDb();
            }
          }

          if (mounted) {
            _workspace.value = _workspace.value.selectConnection(conn);
            _nav.openSqlWorkspaceForConnection(conn);
            SqlEditorCommandBridge.instance.openFileWithContent(
              sql: sql,
              filePath: target.path,
              title: target.fileName,
            );
          }
        }
      } catch (e) {
        if (!mounted) return;
        showAppToast(
          context: context,
          message: 'Failed to open file "${target.fileName}": $e',
          variant: AppToastVariant.error,
        );
      }
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    return ValueListenableBuilder<MainScreenWorkspaceState>(
      valueListenable: _workspace,
      builder: (context, workspace, _) {
        return QueryaCommandHost(
          onToggleSidebar: () => _splitKey.currentState?.toggleSidebar(),
          onNewConnection: () => unawaited(_onNewDatabaseConnectionFromMenu()),
          onReloadConnections: () => unawaited(
              _connectionsPanelKey.currentState?.reloadConnectionsFromDb() ??
                  Future<void>.value()),
          onShowQuickSwitcher: _nav.openQuickSwitcher,
          onOpenSchemaObject: _nav.onOpenSchemaObject,
          onGoHome:
              workspace.activeConnection != null ? _nav.onGoHome : null,
          onCloseWorkspace: _nav.hasCloseableWorkspace(workspace)
              ? () => unawaited(_nav.closeWorkspace())
              : null,
          onConnect: workspace.activeConnection?.id != null
              ? () => _connectionsPanelKey.currentState
                  ?.connect(workspace.activeConnection!.id!)
              : null,
          onDisconnect: workspace.activeConnection != null
              ? () => unawaited(
                    _connectionsPanelKey.currentState
                            ?.disconnect(workspace.activeConnection!) ??
                        Future<void>.value(),
                  )
              : null,
          onReconnect: workspace.activeConnection != null
              ? () => unawaited(
                    _connectionsPanelKey.currentState
                            ?.reconnect(workspace.activeConnection!) ??
                        Future<void>.value(),
                  )
              : null,
          onToggleReadOnly: workspace.activeConnection != null
              ? () => unawaited(_toggleReadOnly())
              : null,
          onOpenWelcomeTour: _onOpenWelcomeTour,
          selectedConnectionId: workspace.activeConnection?.id,
          child: FocusScope(
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

              const material.SingleActivator(
                LogicalKeyboardKey.keyP,
                control: true,
              ): () => unawaited(showCommandPalette(context)),
              const material.SingleActivator(
                LogicalKeyboardKey.keyP,
                meta: true,
              ): () => unawaited(showCommandPalette(context)),
              const material.SingleActivator(
                LogicalKeyboardKey.keyK,
                control: true,
              ): () => _nav.openQuickSwitcher(),
              const material.SingleActivator(
                LogicalKeyboardKey.keyK,
                meta: true,
              ): () => _nav.openQuickSwitcher(),

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
              ): _nav.onGoHome,
              const material.SingleActivator(
                LogicalKeyboardKey.digit0,
                control: true,
                shift: true,
              ): _nav.onGoHome,
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
              onGoHome: _nav.onGoHome,
              child: SqlEditorGlobalActions(
                activeConnection: workspace.activeConnection,
                onOpenSqlWorkspace: _nav.openSqlWorkspaceForConnection,
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
                          onGoHome: _nav.onGoHome,
                          onReadOnlyChanged: () => unawaited(_toggleReadOnly()),
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
                    QueryaDivider(
                        height: 1,
                        color: wb.borderSubtle.withValues(alpha: 0.22)),
                    Expanded(
                      child: MainContentSplit(
                        key: _splitKey,
                        connectionsPanelKey: _connectionsPanelKey,
                        workspace: _workspace,
                        onSidebarVisibilityChanged: (v) =>
                            _isSidebarVisible.value = v,
                        onConnectionSelected: _nav.onConnectionSelected,
                        onPostgresObjectSelected: _nav.onPostgresObjectSelected,
                        onMysqlObjectSelected: _nav.onMysqlObjectSelected,
                        onSqliteObjectSelected: _nav.onSqliteObjectSelected,
                        onExtensionObjectSelected: _nav.onExtensionObjectSelected,
                        onRedisDatabaseSelected: _nav.onRedisDatabaseSelected,
                        onMongoDBDatabaseSelected: _nav.onMongoDBDatabaseSelected,
                        onMongoCollectionSelected: _nav.onMongoCollectionSelected,
                        onPostgresOpenSqlWorkspace: _nav.onPostgresOpenSqlWorkspace,
                        onMysqlOpenSqlWorkspace: _nav.onMysqlOpenSqlWorkspace,
                        onSqliteOpenSqlWorkspace: _nav.onSqliteOpenSqlWorkspace,
                        onRequestNewConnection: _openNewConnectionFromHero,
                        onRequestNewConnectionFromUrl:
                            _onNewDatabaseConnectionFromUrl,
                        onRequestOpenSqlite: _openSqliteFromHero,
                        onRequestLaunchDemo: _onLaunchDemoPlayground,
                        onRequestOpenTour: _onOpenWelcomeTour,
                        onOpenConnection: _nav.onConnectionSelected,
                        initialMongoCollection: _nav.pendingMongoCollection,
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _isSidebarVisible,
                      builder: (context, isSidebarVisible, _) {
                        return ListenableBuilder(
                          listenable: QueryaShellStatus.instance,
                          builder: (context, _) {
                            final status = QueryaShellStatus.instance;
                            return QueryaStatusBar(
                              activeConnection: workspace.activeConnection,
                              isReadOnly: workspace.isReadOnly,
                              isSidebarVisible: isSidebarVisible,
                              onToggleSidebar: () =>
                                  _splitKey.currentState?.toggleSidebar(),
                              onOpenPreferences: () =>
                                  showPreferencesDialog(context),
                              isBusy: status.isBusy,
                              statusMessage: status.statusMessage,
                              rowCount: status.rowCount,
                              columnCount: status.columnCount,
                              lastQueryDuration: status.lastQueryDuration,
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
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
