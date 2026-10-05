import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

bool mysqlObjectOpensTableBrowser(MysqlObjectKind kind) {
  return kind == MysqlObjectKind.table || kind == MysqlObjectKind.view;
}

/// SQL-editor toolbar label for the current transaction state.
String mysqlSqlToolbarTxLabel(bool? txOpen) {
  if (txOpen == null) return 'Transaction: —';
  return txOpen ? 'Transaction: open' : 'Transaction: none';
}

/// Confirms leaving the SQL tab (or opening a table) while a transaction is open.
Future<bool> confirmLeaveOpenMysqlTransaction(
  material.BuildContext context,
) async {
  final ok = await QueryaConfirmDialog.show(
    context: context,
    title: 'Open transaction',
    message: 'The SQL tab has an open transaction. Leave anyway? '
        'Uncommitted work may be lost if the session ends.',
    confirmLabel: 'Leave',
    cancelLabel: 'Stay',
    isDestructive: true,
  );
  return ok == true;
}

/// Warns before opening Table Browser while SQL has an open transaction
/// on the same database.
Future<bool> confirmOpenMysqlTableIfSqlTx(
  material.BuildContext context, {
  required ConnectionRow connection,
  required String database,
  required MysqlObjectKind kind,
}) async {
  if (!mysqlObjectOpensTableBrowser(kind)) return true;
  final open = await MysqlService.instance.hasOpenSqlTransaction(
    connection,
    database: database,
  );
  if (!open) return true;
  if (!context.mounted) return false;
  return confirmLeaveOpenMysqlTransaction(context);
}
