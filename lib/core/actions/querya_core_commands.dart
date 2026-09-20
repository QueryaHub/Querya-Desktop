import 'package:flutter/material.dart' show Icons;
import 'package:shadcn_flutter/shadcn_flutter.dart' show ThemeMode;
import 'package:querya_desktop/core/actions/data_grid_command_bridge.dart';
import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/extensions/presentation/pages/extension_manager_dialog.dart';
import 'package:querya_desktop/features/help/about_dialog.dart';
import 'package:querya_desktop/features/onboarding/welcome_tour_dialog.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/features/updater/update_dialog.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';

/// Built-in commands for Command Palette. Host / bridge actions stay disabled
/// until the matching workspace is mounted (CP-04).
List<QueryaCommand> queryaCoreCommands() {
  final sql = SqlEditorCommandBridge.instance;
  final grid = DataGridCommandBridge.instance;
  return [
    // -- Workspace ----------------------------------------------------------
    QueryaCommand(
      id: 'querya.view.toggleSidebar',
      title: 'Toggle Sidebar',
      category: 'Workspace',
      icon: Icons.view_sidebar_outlined,
      shortcutLabel: 'Ctrl+B',
      aliases: const ['connections', 'panel'],
      isEnabled: (context) =>
          QueryaCommandHost.maybeOf(context)?.onToggleSidebar != null,
      execute: (context) =>
          QueryaCommandHost.maybeOf(context)?.onToggleSidebar?.call(),
    ),
    QueryaCommand(
      id: 'querya.workspace.close',
      title: 'Close Active Workspace',
      category: 'Workspace',
      icon: Icons.close_fullscreen_rounded,
      aliases: const ['unselect', 'stats', 'back'],
      isEnabled: (context) =>
          QueryaCommandHost.maybeOf(context)?.onCloseWorkspace != null,
      execute: (context) =>
          QueryaCommandHost.maybeOf(context)?.onCloseWorkspace?.call(),
    ),
    QueryaCommand(
      id: 'querya.workspace.home',
      title: 'Return to Home',
      category: 'Workspace',
      icon: Icons.home_outlined,
      shortcutLabel: 'Ctrl+Shift+0',
      aliases: const ['start', 'welcome screen'],
      isEnabled: (context) =>
          QueryaCommandHost.maybeOf(context)?.onGoHome != null,
      execute: (context) =>
          QueryaCommandHost.maybeOf(context)?.onGoHome?.call(),
    ),
    QueryaCommand(
      id: 'querya.goto.object',
      title: 'Go to Table or View…',
      category: 'Workspace',
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

    // -- Connection ---------------------------------------------------------
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
      id: 'querya.connection.connect',
      title: 'Connect',
      category: 'Connection',
      icon: Icons.link_rounded,
      aliases: const ['open', 'expand'],
      isEnabled: (context) =>
          QueryaCommandHost.maybeOf(context)?.onConnect != null,
      execute: (context) =>
          QueryaCommandHost.maybeOf(context)?.onConnect?.call(),
    ),
    QueryaCommand(
      id: 'querya.connection.disconnect',
      title: 'Disconnect',
      category: 'Connection',
      icon: Icons.link_off_rounded,
      aliases: const ['close connection'],
      isEnabled: (context) =>
          QueryaCommandHost.maybeOf(context)?.onDisconnect != null,
      execute: (context) =>
          QueryaCommandHost.maybeOf(context)?.onDisconnect?.call(),
    ),
    QueryaCommand(
      id: 'querya.connection.reconnect',
      title: 'Reconnect',
      category: 'Connection',
      icon: Icons.refresh_rounded,
      aliases: const ['invalidate', 'reload connection'],
      isEnabled: (context) =>
          QueryaCommandHost.maybeOf(context)?.onReconnect != null,
      execute: (context) =>
          QueryaCommandHost.maybeOf(context)?.onReconnect?.call(),
    ),
    QueryaCommand(
      id: 'querya.connection.toggleReadOnly',
      title: 'Toggle Read-Only Mode',
      category: 'Connection',
      icon: Icons.lock_outline_rounded,
      aliases: const ['readonly', 'write', 'ro'],
      isEnabled: (context) =>
          QueryaCommandHost.maybeOf(context)?.onToggleReadOnly != null,
      execute: (context) =>
          QueryaCommandHost.maybeOf(context)?.onToggleReadOnly?.call(),
    ),

    // -- SQL ----------------------------------------------------------------
    QueryaCommand(
      id: 'querya.sql.execute',
      title: 'Execute Query',
      category: 'SQL',
      icon: Icons.play_arrow_rounded,
      shortcutLabel: 'Ctrl+Enter',
      aliases: const ['run', 'query'],
      isEnabled: (_) => sql.canExecute,
      execute: (_) => sql.invokeExecute(),
    ),
    QueryaCommand(
      id: 'querya.sql.newTab',
      title: 'New Query Tab',
      category: 'SQL',
      icon: Icons.add_box_outlined,
      shortcutLabel: 'Ctrl+T',
      aliases: const ['tab'],
      isEnabled: (_) => sql.isActive,
      execute: (_) => sql.invokeNew(),
    ),
    QueryaCommand(
      id: 'querya.sql.closeTab',
      title: 'Close Current Tab',
      category: 'SQL',
      icon: Icons.close_rounded,
      shortcutLabel: 'Ctrl+W',
      aliases: const ['close tab'],
      isEnabled: (_) => sql.canCloseTab,
      execute: (_) => sql.invokeCloseTab(),
    ),
    QueryaCommand(
      id: 'querya.sql.format',
      title: 'Format SQL Query',
      category: 'SQL',
      icon: Icons.auto_fix_high_rounded,
      shortcutLabel: 'Shift+Alt+F',
      aliases: const ['pretty', 'indent'],
      isEnabled: (_) => sql.canFormat,
      execute: (_) => sql.invokeFormat(),
    ),
    QueryaCommand(
      id: 'querya.sql.clear',
      title: 'Clear Editor',
      category: 'SQL',
      icon: Icons.backspace_outlined,
      aliases: const ['empty', 'reset editor'],
      isEnabled: (_) => sql.canClear,
      execute: (_) => sql.invokeClear(),
    ),

    // -- Data Grid ----------------------------------------------------------
    QueryaCommand(
      id: 'querya.grid.toggleFilter',
      title: 'Toggle Quick Filter',
      category: 'Data Grid',
      icon: Icons.filter_alt_outlined,
      shortcutLabel: 'Ctrl+F',
      aliases: const ['search rows', 'filter'],
      isEnabled: (_) => grid.isActive,
      execute: (_) => grid.invokeToggleFilter(),
    ),
    QueryaCommand(
      id: 'querya.grid.inspectCell',
      title: 'Inspect Cell Panel',
      category: 'Data Grid',
      icon: Icons.data_object_rounded,
      aliases: const ['value panel', 'json'],
      isEnabled: (_) => grid.isActive,
      execute: (_) => grid.invokeToggleInspector(),
    ),
    QueryaCommand(
      id: 'querya.grid.copyCsv',
      title: 'Copy as CSV',
      category: 'Data Grid',
      icon: Icons.table_chart_outlined,
      aliases: const ['clipboard csv'],
      isEnabled: (_) => grid.canCopy,
      execute: (_) => grid.invokeCopy(DataExportFormat.csv),
    ),
    QueryaCommand(
      id: 'querya.grid.copyJson',
      title: 'Copy as JSON',
      category: 'Data Grid',
      icon: Icons.data_object_outlined,
      aliases: const ['clipboard json'],
      isEnabled: (_) => grid.canCopy,
      execute: (_) => grid.invokeCopy(DataExportFormat.json),
    ),
    QueryaCommand(
      id: 'querya.grid.copyMarkdown',
      title: 'Copy as Markdown',
      category: 'Data Grid',
      icon: Icons.code_rounded,
      aliases: const ['clipboard md', 'md table'],
      isEnabled: (_) => grid.canCopy,
      execute: (_) => grid.invokeCopy(DataExportFormat.markdown),
    ),
    QueryaCommand(
      id: 'querya.grid.saveExport',
      title: 'Save Export File',
      category: 'Data Grid',
      icon: Icons.download_rounded,
      aliases: const ['export file', 'save csv'],
      isEnabled: (_) => grid.canCopy,
      execute: (_) => grid.invokeSaveExport(),
    ),
    QueryaCommand(
      id: 'querya.grid.applyStaged',
      title: 'Apply Staged Edits',
      category: 'Data Grid',
      icon: Icons.save_outlined,
      shortcutLabel: 'Ctrl+S',
      aliases: const ['commit', 'save changes', 'dml'],
      isEnabled: (_) => grid.canApplyStaged,
      execute: (_) => grid.invokeApplyStaged(),
    ),

    // -- Application --------------------------------------------------------
    const QueryaCommand(
      id: 'querya.app.preferences',
      title: 'Open Preferences',
      category: 'Application',
      icon: Icons.settings_outlined,
      shortcutLabel: 'Ctrl+,',
      aliases: ['settings', 'options'],
      execute: showPreferencesDialog,
    ),
    const QueryaCommand(
      id: 'querya.app.extensions',
      title: 'Open Extension Manager',
      category: 'Application',
      icon: Icons.extension_outlined,
      aliases: ['plugins', 'marketplace'],
      execute: showExtensionManagerDialog,
    ),
    const QueryaCommand(
      id: 'querya.app.updates',
      title: 'Check for Updates',
      category: 'Application',
      icon: Icons.system_update_alt_rounded,
      aliases: ['upgrade', 'version'],
      execute: showUpdateDialog,
    ),
    QueryaCommand(
      id: 'querya.app.welcome',
      title: 'Welcome Tour',
      category: 'Application',
      icon: Icons.auto_awesome_outlined,
      shortcutLabel: 'F1',
      aliases: const ['tutorial', 'onboarding', 'help'],
      execute: (context) {
        final host = QueryaCommandHost.maybeOf(context);
        if (host?.onOpenWelcomeTour != null) {
          host!.onOpenWelcomeTour!();
          return;
        }
        showWelcomeTourDialog(context);
      },
    ),
    const QueryaCommand(
      id: 'querya.app.about',
      title: 'About Querya',
      category: 'Application',
      icon: Icons.info_outline_rounded,
      aliases: ['version', 'license'],
      execute: showAboutDialog,
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
