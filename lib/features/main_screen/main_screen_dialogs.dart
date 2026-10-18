import 'package:flutter/widgets.dart';
import 'dart:async';

import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/demo/demo_playground_service.dart';
import 'package:querya_desktop/core/platform/file_launch_service.dart';
import 'package:querya_desktop/core/security/safe_mode.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/features/connections/new_connection_url_dialog.dart';
import 'package:querya_desktop/features/connections/sqlite_connection_form.dart';
import 'package:querya_desktop/features/main_screen/main_screen_navigator.dart';
import 'package:querya_desktop/features/main_screen/main_screen_workspace_state.dart';
import 'package:querya_desktop/features/main_screen/safe_mode_unlock_dialog.dart';
import 'package:querya_desktop/features/onboarding/welcome_tour_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// The modal flows of the shell: a new connection (form, URL, SQLite file),
/// the welcome tour and the demo playground, files opened from the file
/// manager, and the read-only lock with its Safe Mode confirmation.
class MainScreenDialogs {
  MainScreenDialogs({
    required this.workspace,
    required this.nav,
    required this.connectionsPanelKey,
    required BuildContext Function() context,
    required bool Function() mounted,
  })  : _context = context,
        _mounted = mounted;

  final ValueNotifier<MainScreenWorkspaceState> workspace;
  final MainScreenNavigator nav;
  final GlobalKey<ConnectionsPanelState> connectionsPanelKey;
  final BuildContext Function() _context;
  final bool Function() _mounted;

  bool _openingConnectionDialog = false;

  Timer? _safeModeRelockTimer;

  /// Toggles the read-only lock. Turning it off for a Production connection
  /// (Safe Mode) needs a typed confirmation and re-locks after
  /// [kSafeModeUnlockDuration].
  Future<void> toggleReadOnly() async {
    final ws = workspace.value;
    final connection = ws.activeConnection;
    if (connection == null) return;

    if (ws.isReadOnly &&
        safeModeRequiresConfirmation(connection.environment)) {
      final confirmed = await showSafeModeUnlockDialog(
        context: _context(),
        connectionName: connection.name,
      );
      if (!confirmed || !_mounted()) return;
      final current = workspace.value;
      if (current.activeConnection?.id != connection.id || !current.isReadOnly) {
        return;
      }
      workspace.value = current.toggleReadOnly();
      _safeModeRelockTimer?.cancel();
      _safeModeRelockTimer = Timer(kSafeModeUnlockDuration, () {
        if (!_mounted()) return;
        final latest = workspace.value;
        if (latest.activeConnection?.id == connection.id &&
            !latest.isReadOnly) {
          workspace.value = latest.toggleReadOnly();
          showAppToast(
            context: _context(),
            message: '${connection.name} is read-only again',
          );
        }
      });
      return;
    }

    _safeModeRelockTimer?.cancel();
    workspace.value = ws.toggleReadOnly();
  }

  Future<void> openNewConnectionFromHero() async {
    final row = await promptCreateConnection(_context());
    if (!_mounted() || row == null) return;
    await LocalDb.instance.addConnection(row);
    await connectionsPanelKey.currentState?.reloadConnectionsFromDb();
  }

  Future<void> onNewDatabaseConnectionFromMenu() async {
    if (_openingConnectionDialog) return;
    _openingConnectionDialog = true;
    try {
      // Menu overlay _context() is torn down before the connection form opens.
      await Future.delayed(const Duration(milliseconds: 100));
      if (!_mounted()) return;
      final row = await promptCreateConnection(_context(), folderId: null);
      if (!_mounted() || row == null) return;
      await LocalDb.instance.addConnection(row);
      await connectionsPanelKey.currentState?.reloadConnectionsFromDb();
    } finally {
      _openingConnectionDialog = false;
    }
  }

  Future<void> onNewDatabaseConnectionFromUrl() async {
    if (_openingConnectionDialog) return;
    _openingConnectionDialog = true;
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!_mounted()) return;
      final row = await showNewConnectionUrlDialog(_context());
      if (!_mounted() || row == null) return;
      await LocalDb.instance.addConnection(row);
      await connectionsPanelKey.currentState?.reloadConnectionsFromDb();
    } finally {
      _openingConnectionDialog = false;
    }
  }

  Future<void> openSqliteFromHero() async {
    final row = await showSqliteConnectionForm(_context());
    if (!_mounted() || row == null) return;
    await LocalDb.instance.addConnection(row);
    await connectionsPanelKey.currentState?.reloadConnectionsFromDb();
  }

  void onOpenWelcomeTour() {
    showWelcomeTourDialog(
      _context(),
      onLaunchDemo: onLaunchDemoPlayground,
      onGoHome: workspace.value.activeConnection != null ? nav.onGoHome : null,
    );
  }

  Future<void> onLaunchDemoPlayground() async {
    try {
      final demoConn = await DemoPlaygroundService.getOrCreateDemoConnection();
      if (!_mounted()) return;
      await connectionsPanelKey.currentState?.reloadConnectionsFromDb();
      workspace.value = workspace.value.selectConnection(demoConn);
      nav.onSqliteOpenSqlWorkspace(demoConn);
    } catch (_) {}
  }

  Future<void> handlePendingFileLaunch() async {
    final targets = FileLaunchService.instance.consumePendingTargets();
    if (targets.isEmpty || !_mounted()) return;

    for (final target in targets) {
      if (!_mounted()) return;
      try {
        if (target.kind == FileLaunchKind.sqlite) {
          final conn = await FileLaunchService.instance
              .resolveOrRegisterSqliteConnection(target);
          if (!_mounted()) return;
          await connectionsPanelKey.currentState?.reloadConnectionsFromDb();
          workspace.value = workspace.value.selectConnection(conn);
          nav.onSqliteOpenSqlWorkspace(conn);
        } else if (target.kind == FileLaunchKind.sql) {
          final sql = await FileLaunchService.instance.readSqlContent(target);
          if (!_mounted()) return;

          var conn = workspace.value.activeConnection;
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
              await connectionsPanelKey.currentState?.reloadConnectionsFromDb();
            }
          }

          if (_mounted()) {
            workspace.value = workspace.value.selectConnection(conn);
            nav.openSqlWorkspaceForConnection(conn);
            SqlEditorCommandBridge.instance.openFileWithContent(
              sql: sql,
              filePath: target.path,
              title: target.fileName,
            );
          }
        }
      } catch (e) {
        if (!_mounted()) return;
        showAppToast(
          context: _context(),
          message: 'Failed to open file "${target.fileName}": $e',
          variant: AppToastVariant.error,
        );
      }
    }
  }

  void dispose() {
    _safeModeRelockTimer?.cancel();
  }
}
