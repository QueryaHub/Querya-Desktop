import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart'
    show SqliteObjectKind;
import 'package:querya_desktop/shared/widgets/widgets.dart';

bool sqliteObjectOpensTableBrowser(SqliteObjectKind kind) {
  return kind == SqliteObjectKind.table || kind == SqliteObjectKind.view;
}

/// Confirms leaving the SQL tab (or opening a table) while a transaction is open.
Future<bool> confirmLeaveOpenSqliteTransaction(
  material.BuildContext context,
) async {
  final ok = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => material.AlertDialog(
      title: const material.Text('Open transaction'),
      content: const material.Text(
        'The SQL tab has an open transaction. Leave anyway? '
        'Uncommitted work may be lost if the session ends.',
      ),
      actions: [
        material.TextButton(
          onPressed: () => material.Navigator.of(ctx).pop(false),
          child: const material.Text('Stay'),
        ),
        material.TextButton(
          onPressed: () => material.Navigator.of(ctx).pop(true),
          child: const material.Text('Leave'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Warns before opening Table Browser while the SQL editor has a `BEGIN`.
Future<bool> confirmOpenSqliteTableIfSqlTx(
  material.BuildContext context, {
  required ConnectionRow connection,
  required SqliteObjectKind kind,
}) async {
  if (!sqliteObjectOpensTableBrowser(kind)) return true;
  final open = await SqliteService.instance.hasOpenSqlTransaction(connection);
  if (!open) return true;
  if (!context.mounted) return false;
  return confirmLeaveOpenSqliteTransaction(context);
}
