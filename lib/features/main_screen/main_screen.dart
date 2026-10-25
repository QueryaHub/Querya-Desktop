import 'package:flutter/widgets.dart';
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
import 'package:querya_desktop/core/platform/file_launch_service.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/extensions/sandbox/unsandboxed_launch_consent_gate.dart';
import 'package:querya_desktop/features/extensions/presentation/widgets/unsandboxed_driver_consent_dialog.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/features/help/log_actions.dart';
import 'package:querya_desktop/features/macos/querya_platform_menu_bar.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'main_screen_workspace_state.dart';
import 'main_content_split.dart';
import 'main_screen_chrome.dart';
import 'main_screen_dialogs.dart';
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
  late final MainScreenDialogs _dialogs = MainScreenDialogs(
    workspace: _workspace,
    nav: _nav,
    connectionsPanelKey: _connectionsPanelKey,
    context: () => context,
    mounted: () => mounted,
  );
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
          _dialogs.onOpenWelcomeTour();
        }
      }
      if (mounted) {
        await _dialogs.handlePendingFileLaunch();
      }
    });
  }

  void _onFilesQueued() {
    if (mounted) unawaited(_dialogs.handlePendingFileLaunch());
  }

  @override
  void dispose() {
    FileLaunchService.instance.pendingRevision.removeListener(_onFilesQueued);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    UnsandboxedLaunchConsentGate.instance.handler = null;
    _dialogs.dispose();
    _workspace.dispose();
    _isSidebarVisible.dispose();
    super.dispose();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // A dialog or sheet is on top: the screen's shortcuts must not reach
    // through it (Ctrl+N over the welcome tour opened a second dialog, #1820).
    if (ModalRoute.of(context)?.isCurrent == false) return false;

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
        unawaited(_dialogs.onNewDatabaseConnectionFromMenu());
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
        _dialogs.onOpenWelcomeTour();
      case MainShortcut.goHome:
        _nav.onGoHome();
    }
    return true;
  }

  /// Runs [intent] on the focused editor, if one handles it.
  void _invoke(Intent intent) => Actions.maybeInvoke(
      FocusManager.instance.primaryFocus?.context ?? context, intent);

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    return ValueListenableBuilder<MainScreenWorkspaceState>(
      valueListenable: _workspace,
      builder: (context, workspace, _) {
        return QueryaCommandHost(
          onToggleSidebar: () => _splitKey.currentState?.toggleSidebar(),
          onNewConnection: () =>
              unawaited(_dialogs.onNewDatabaseConnectionFromMenu()),
          onReloadConnections: () => unawaited(
              _connectionsPanelKey.currentState?.reloadConnectionsFromDb() ??
                  Future<void>.value()),
          onShowQuickSwitcher: _nav.openQuickSwitcher,
          onOpenSchemaObject: _nav.onOpenSchemaObject,
          onGoHome: workspace.activeConnection != null ? _nav.onGoHome : null,
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
              ? () => unawaited(_dialogs.toggleReadOnly())
              : null,
          onOpenWelcomeTour: _dialogs.onOpenWelcomeTour,
          selectedConnectionId: workspace.activeConnection?.id,
          child: FocusScope(
            autofocus: true,
            child: material.CallbackShortcuts(
              bindings: {
                // New Database Connection: Ctrl+N / Cmd+N
                const material.SingleActivator(
                  LogicalKeyboardKey.keyN,
                  meta: true,
                ): () => unawaited(_dialogs.onNewDatabaseConnectionFromMenu()),
                const material.SingleActivator(
                  LogicalKeyboardKey.keyN,
                  control: true,
                ): () => unawaited(_dialogs.onNewDatabaseConnectionFromMenu()),

                // New Query Tab: Ctrl+Shift+N / Cmd+Shift+N
                const material.SingleActivator(
                  LogicalKeyboardKey.keyN,
                  meta: true,
                  shift: true,
                ): () => _invoke(const NewSqlIntent()),
                const material.SingleActivator(
                  LogicalKeyboardKey.keyN,
                  control: true,
                  shift: true,
                ): () => _invoke(const NewSqlIntent()),

                // Open SQL File: Ctrl+O / Cmd+O
                const material.SingleActivator(
                  LogicalKeyboardKey.keyO,
                  meta: true,
                ): () => _invoke(const OpenSqlIntent()),
                const material.SingleActivator(
                  LogicalKeyboardKey.keyO,
                  control: true,
                ): () => _invoke(const OpenSqlIntent()),

                // Save SQL File: Ctrl+S / Cmd+S
                const material.SingleActivator(
                  LogicalKeyboardKey.keyS,
                  meta: true,
                ): () => _invoke(const SaveSqlIntent()),
                const material.SingleActivator(
                  LogicalKeyboardKey.keyS,
                  control: true,
                ): () => _invoke(const SaveSqlIntent()),

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
                ): () => _dialogs.onOpenWelcomeTour(),
                const material.SingleActivator(
                  LogicalKeyboardKey.keyH,
                  meta: true,
                  shift: true,
                ): () => _dialogs.onOpenWelcomeTour(),
                const material.SingleActivator(
                  LogicalKeyboardKey.keyH,
                  control: true,
                  shift: true,
                ): () => _dialogs.onOpenWelcomeTour(),

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
                    unawaited(_dialogs.onNewDatabaseConnectionFromMenu()),
                onNewQueryTab: () => _invoke(const NewSqlIntent()),
                onOpenSqlScript: () => _invoke(const OpenSqlIntent()),
                onSaveQuery: () => _invoke(const SaveSqlIntent()),
                onExecuteQuery: () =>
                    SqlEditorCommandBridge.instance.invokeExecute(),
                onToggleSidebar: () => _splitKey.currentState?.toggleSidebar(),
                onOpenPreferences: () => showPreferencesDialog(context),
                onOpenWelcomeTour: () => _dialogs.onOpenWelcomeTour(),
                onOpenLogsFolder: () => unawaited(openLogsFolder(context)),
                onCopyDiagnostics: () => unawaited(copyDiagnostics(context)),
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
                          ShellTitleBar(
                            workspace: workspace,
                            isSidebarVisible: _isSidebarVisible,
                            connectionsPanelKey: _connectionsPanelKey,
                            onToggleSidebar: () =>
                                _splitKey.currentState?.toggleSidebar(),
                            dialogs: _dialogs,
                            nav: _nav,
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
                              onPostgresObjectSelected:
                                  _nav.onPostgresObjectSelected,
                              onMysqlObjectSelected: _nav.onMysqlObjectSelected,
                              onSqliteObjectSelected:
                                  _nav.onSqliteObjectSelected,
                              onExtensionObjectSelected:
                                  _nav.onExtensionObjectSelected,
                              onRedisDatabaseSelected:
                                  _nav.onRedisDatabaseSelected,
                              onMongoDBDatabaseSelected:
                                  _nav.onMongoDBDatabaseSelected,
                              onMongoCollectionSelected:
                                  _nav.onMongoCollectionSelected,
                              onPostgresOpenSqlWorkspace:
                                  _nav.onPostgresOpenSqlWorkspace,
                              onMysqlOpenSqlWorkspace:
                                  _nav.onMysqlOpenSqlWorkspace,
                              onSqliteOpenSqlWorkspace:
                                  _nav.onSqliteOpenSqlWorkspace,
                              onRequestNewConnection:
                                  _dialogs.openNewConnectionFromHero,
                              onRequestNewConnectionFromUrl:
                                  _dialogs.onNewDatabaseConnectionFromUrl,
                              onRequestOpenSqlite: _dialogs.openSqliteFromHero,
                              onRequestLaunchDemo:
                                  _dialogs.onLaunchDemoPlayground,
                              onRequestOpenTour: _dialogs.onOpenWelcomeTour,
                              onOpenConnection: _nav.onConnectionSelected,
                              initialMongoCollection:
                                  _nav.pendingMongoCollection,
                            ),
                          ),
                          ShellStatusBar(
                            workspace: workspace,
                            isSidebarVisible: _isSidebarVisible,
                            onToggleSidebar: () =>
                                _splitKey.currentState?.toggleSidebar(),
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
