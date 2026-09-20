import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Kinds that open Table Browser (SELECT on a dedicated session).
bool postgresObjectOpensTableBrowser(PostgresObjectKind kind) {
  return kind == PostgresObjectKind.table ||
      kind == PostgresObjectKind.view ||
      kind == PostgresObjectKind.materializedView;
}

/// Confirms leaving the SQL tab (or opening a table) while a transaction is open.
Future<bool> confirmLeaveOpenPostgresTransaction(
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

/// Warns before opening Table Browser on a database whose SQL editor has a tx.
Future<bool> confirmOpenPostgresTableIfSqlTx(
  material.BuildContext context, {
  required ConnectionRow connection,
  required String database,
  required PostgresObjectKind kind,
}) async {
  if (!postgresObjectOpensTableBrowser(kind)) return true;
  final open = await PostgresService.instance.hasOpenSqlTransaction(
    connection,
    database: database,
  );
  if (!open) return true;
  if (!context.mounted) return false;
  return confirmLeaveOpenPostgresTransaction(context);
}
