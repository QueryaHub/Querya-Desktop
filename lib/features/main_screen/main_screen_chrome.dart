import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/ui/querya_shell_status.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/features/main_screen/main_screen_dialogs.dart';
import 'package:querya_desktop/features/main_screen/main_screen_navigator.dart';
import 'package:querya_desktop/features/main_screen/main_screen_workspace_state.dart';
import 'package:querya_desktop/features/main_screen/querya_status_bar.dart';
import 'package:querya_desktop/features/main_screen/querya_window_title_bar.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';

/// The window title bar wired to the workspace: connect, disconnect, the
/// read-only lock, the new-connection entries and the tour.
class ShellTitleBar extends material.StatelessWidget {
  const ShellTitleBar({
    super.key,
    required this.workspace,
    required this.isSidebarVisible,
    required this.connectionsPanelKey,
    required this.onToggleSidebar,
    required this.dialogs,
    required this.nav,
  });

  final MainScreenWorkspaceState workspace;
  final ValueListenable<bool> isSidebarVisible;
  final material.GlobalKey<ConnectionsPanelState> connectionsPanelKey;
  final material.VoidCallback onToggleSidebar;
  final MainScreenDialogs dialogs;
  final MainScreenNavigator nav;

  @override
  material.Widget build(material.BuildContext context) {
    final panel = connectionsPanelKey;
    return material.ValueListenableBuilder<bool>(
      valueListenable: isSidebarVisible,
      builder: (context, visible, _) {
        return QueryaWindowTitleBar(
          onNewDatabaseConnection: dialogs.onNewDatabaseConnectionFromMenu,
          onNewDatabaseConnectionFromUrl: dialogs.onNewDatabaseConnectionFromUrl,
          activeConnection: workspace.activeConnection,
          isReadOnly: workspace.isReadOnly,
          isSidebarVisible: visible,
          onToggleSidebar: onToggleSidebar,
          onOpenWelcomeTour: dialogs.onOpenWelcomeTour,
          onGoHome: nav.onGoHome,
          onReadOnlyChanged: () => unawaited(dialogs.toggleReadOnly()),
          onConnect: () {
            final id = workspace.activeConnection?.id;
            if (id != null) panel.currentState?.connect(id);
          },
          onReconnect: () {
            final active = workspace.activeConnection;
            if (active != null) panel.currentState?.reconnect(active);
          },
          onDisconnect: () {
            final active = workspace.activeConnection;
            if (active != null) panel.currentState?.disconnect(active);
          },
          onDisconnectAll: () => panel.currentState?.disconnectAll(),
          onDisconnectOthers: () {
            final active = workspace.activeConnection;
            if (active != null) panel.currentState?.disconnectOthers(active);
          },
        );
      },
    );
  }
}

/// The status bar fed by [QueryaShellStatus].
class ShellStatusBar extends material.StatelessWidget {
  const ShellStatusBar({
    super.key,
    required this.workspace,
    required this.isSidebarVisible,
    required this.onToggleSidebar,
  });

  final MainScreenWorkspaceState workspace;
  final ValueListenable<bool> isSidebarVisible;
  final material.VoidCallback onToggleSidebar;

  @override
  material.Widget build(material.BuildContext context) {
    return material.ValueListenableBuilder<bool>(
      valueListenable: isSidebarVisible,
      builder: (context, visible, _) {
        return material.ListenableBuilder(
          listenable: QueryaShellStatus.instance,
          builder: (context, _) {
            final status = QueryaShellStatus.instance;
            return QueryaStatusBar(
              activeConnection: workspace.activeConnection,
              isReadOnly: workspace.isReadOnly,
              isSidebarVisible: visible,
              onToggleSidebar: onToggleSidebar,
              onOpenPreferences: () => showPreferencesDialog(context),
              isBusy: status.isBusy,
              statusMessage: status.statusMessage,
              rowCount: status.rowCount,
              columnCount: status.columnCount,
              lastQueryDuration: status.lastQueryDuration,
            );
          },
        );
      },
    );
  }
}
