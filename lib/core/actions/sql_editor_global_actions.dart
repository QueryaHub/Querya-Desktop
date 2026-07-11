import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/actions/sql_connection_types.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Fallback [Actions] for File → New/Open/Save when focus is outside a SQL
/// workspace (title bar, table view, MongoDB/Redis, empty workspace).
class SqlEditorGlobalActions extends StatelessWidget {
  const SqlEditorGlobalActions({
    super.key,
    required this.activeConnection,
    required this.onOpenSqlWorkspace,
    required this.child,
  });

  final ConnectionRow? activeConnection;
  final void Function(ConnectionRow connection) onOpenSqlWorkspace;
  final Widget child;

  static const _noSqlConnectionMessage =
      'Select a SQL-capable connection (PostgreSQL, MySQL, SQLite, or an installed driver) to edit SQL files.';

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        NewSqlIntent: CallbackAction<NewSqlIntent>(
          onInvoke: (_) {
            _handleNew(context);
            return null;
          },
        ),
        OpenSqlIntent: CallbackAction<OpenSqlIntent>(
          onInvoke: (_) {
            _handleOpen(context);
            return null;
          },
        ),
        SaveSqlIntent: CallbackAction<SaveSqlIntent>(
          onInvoke: (_) {
            _handleSave(context);
            return null;
          },
        ),
      },
      child: child,
    );
  }

  void _handleNew(material.BuildContext context) {
    final bridge = SqlEditorCommandBridge.instance;
    if (bridge.isActive) {
      bridge.invokeNew();
      return;
    }
    final connection = activeConnection;
    if (!isSqlCapableConnection(connection)) {
      _showHint(context, _noSqlConnectionMessage);
      return;
    }
    bridge.queuePending(SqlEditorPendingAction.newQuery);
    onOpenSqlWorkspace(connection!);
  }

  void _handleOpen(material.BuildContext context) {
    final bridge = SqlEditorCommandBridge.instance;
    if (bridge.isActive) {
      bridge.invokeOpen();
      return;
    }
    final connection = activeConnection;
    if (!isSqlCapableConnection(connection)) {
      _showHint(context, _noSqlConnectionMessage);
      return;
    }
    bridge.queuePending(SqlEditorPendingAction.openFile);
    onOpenSqlWorkspace(connection!);
  }

  void _handleSave(material.BuildContext context) {
    final bridge = SqlEditorCommandBridge.instance;
    if (bridge.isActive) {
      bridge.invokeSave();
      return;
    }
    final connection = activeConnection;
    if (!isSqlCapableConnection(connection)) {
      _showHint(context, _noSqlConnectionMessage);
      return;
    }
    bridge.queuePending(SqlEditorPendingAction.saveFile);
    onOpenSqlWorkspace(connection!);
  }

  static void _showHint(material.BuildContext context, String message) {
    material.ScaffoldMessenger.of(context).showSnackBar(
      material.SnackBar(content: material.Text(message)),
    );
  }
}
