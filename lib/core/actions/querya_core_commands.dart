import 'package:flutter/material.dart' show Icons;
import 'package:shadcn_flutter/shadcn_flutter.dart' show ThemeMode;
import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';

/// Built-in commands for Command Palette (CP-01). Host-only actions stay
/// disabled until [QueryaCommandHost] is above the tree (CP-02 / CP-04).
List<QueryaCommand> queryaCoreCommands() {
  return [
    QueryaCommand(
      id: 'querya.connection.new',
      title: 'New Connection',
      category: 'Connection',
      icon: Icons.add_rounded,
      shortcutLabel: 'Ctrl+N',
      aliases: const ['database', 'connect', 'add'],
      execute: (context) {
        final host = QueryaCommandHost.maybeOf(context);
        if (host?.onNewConnection != null) {
          host!.onNewConnection!();
          return;
        }
        promptCreateConnection(context);
      },
    ),
    QueryaCommand(
      id: 'querya.sql.execute',
      title: 'Execute Query',
      category: 'SQL',
      icon: Icons.play_arrow_rounded,
      shortcutLabel: 'Ctrl+Enter',
      aliases: const ['run', 'query'],
      isEnabled: (_) => SqlEditorCommandBridge.instance.canExecute,
      execute: (_) => SqlEditorCommandBridge.instance.invokeExecute(),
    ),
    QueryaCommand(
      id: 'querya.view.toggleSidebar',
      title: 'Toggle Sidebar',
      category: 'View',
      icon: Icons.view_sidebar_outlined,
      shortcutLabel: 'Ctrl+B',
      aliases: const ['connections', 'panel'],
      isEnabled: (context) =>
          QueryaCommandHost.maybeOf(context)?.onToggleSidebar != null,
      execute: (context) =>
          QueryaCommandHost.maybeOf(context)?.onToggleSidebar?.call(),
    ),
    QueryaCommand(
      id: 'querya.goto.object',
      title: 'Go to Table or View…',
      category: 'Navigation',
      icon: Icons.search_rounded,
      shortcutLabel: 'Ctrl+K',
      aliases: const [
        'quick switcher',
        'goto',
        'table',
        'jump',
        '#',
        '@',
      ],
      isEnabled: (context) =>
          QueryaCommandHost.maybeOf(context)?.onShowQuickSwitcher != null,
      execute: (context) =>
          QueryaCommandHost.maybeOf(context)?.onShowQuickSwitcher?.call(''),
    ),
    const QueryaCommand(
      id: 'querya.app.preferences',
      title: 'Open Preferences',
      category: 'Application',
      icon: Icons.settings_outlined,
      shortcutLabel: 'Ctrl+,',
      aliases: ['settings', 'options'],
      execute: showPreferencesDialog,
    ),
    QueryaCommand(
      id: 'querya.theme.toggle',
      title: 'Toggle Dark/Light Theme',
      category: 'Application',
      icon: Icons.contrast,
      aliases: const ['dark', 'light', 'appearance', 'mode'],
      execute: (_) {
        final controller = ThemeController.instance;
        final next = controller.themeMode == ThemeMode.light
            ? ThemeMode.dark
            : ThemeMode.light;
        controller.setThemeMode(next);
      },
    ),
  ];
}
