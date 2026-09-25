import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/dml_preview_dialog.dart';
import 'package:querya_desktop/features/workspace/save_error_description.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Outcome of [loadTableViewSchema] (success vs swallowed getTableSchema error).
class TableViewSchemaLoad {
  const TableViewSchemaLoad._({this.schema, this.error});

  const TableViewSchemaLoad.ok(TableSchemaMeta schema) : this._(schema: schema);

  const TableViewSchemaLoad.failed(Object error) : this._(error: error);

  final TableSchemaMeta? schema;
  final Object? error;

  bool get isOk => schema != null;
}

/// Runs [fetch] and captures a failure instead of treating it as “no PK”.
Future<TableViewSchemaLoad> loadTableViewSchema(
  Future<TableSchemaMeta> Function() fetch,
) async {
  try {
    return TableViewSchemaLoad.ok(await fetch());
  } catch (e) {
    return TableViewSchemaLoad.failed(e);
  }
}

/// Status copy when [loadTableViewSchema] failed. Editing stays off.
String tableViewSchemaUnavailableReason(Object error) {
  return 'Cannot edit: schema unavailable. $error. Refresh to retry.';
}

/// Whether Table Browser should attach a [DataGridStagingBuffer] for this page.
bool tableViewEditingEnabled({
  required bool isView,
  bool isMaterializedView = false,
  required bool customSqlActive,
  required bool hasPrimaryKey,
  bool readOnly = false,
  Object? schemaError,
}) {
  if (readOnly || isView || isMaterializedView || customSqlActive) return false;
  if (schemaError != null) return false;
  return hasPrimaryKey;
}

/// Human-readable reason editing is off, or null when it is allowed / not yet known.
String? tableViewEditDisabledReason({
  required bool isView,
  bool isMaterializedView = false,
  required bool customSqlActive,
  required bool hasPrimaryKey,
  required bool schemaLoaded,
  bool readOnly = false,
  Object? schemaError,
}) {
  if (readOnly) return 'Read-only session';
  if (isView || isMaterializedView) return 'Views are read-only';
  if (customSqlActive) return 'Custom SQL results are read-only';
  if (schemaError != null) {
    return tableViewSchemaUnavailableReason(schemaError);
  }
  if (schemaLoaded && !hasPrimaryKey) {
    return 'Cannot edit: no primary key detected';
  }
  return null;
}

/// Column name → SQL type from [schema], omitting empty types.
Map<String, String> columnDataTypesFromSchema(TableSchemaMeta schema) {
  return {
    for (final c in schema.columns)
      if (c.dataType.isNotEmpty) c.name: c.dataType,
  };
}

/// Column name → schema flags used by INSERT (generated / defaults).
Map<String, TableColumnMeta> columnMetaFromSchema(TableSchemaMeta schema) {
  return {for (final c in schema.columns) c.name: c};
}

/// Disposes [previous] and returns a new buffer when [enabled].
DataGridStagingBuffer? replaceTableViewStagingBuffer({
  DataGridStagingBuffer? previous,
  required List<String> columns,
  required List<List<String>> rows,
  required bool enabled,
  List<String> primaryKeys = const [],
}) {
  previous?.dispose();
  if (!enabled || columns.isEmpty) return null;
  return DataGridStagingBuffer(
    columns: columns,
    rows: rows,
    primaryKeys: primaryKeys,
  );
}

/// Confirms discarding dirty staged edits. Returns true when it is safe to proceed.
Future<bool> confirmDiscardTableEditsIfDirty({
  required material.BuildContext context,
  required DataGridStagingBuffer? buffer,
  required String tableTitle,
}) async {
  if (buffer == null || !buffer.isDirty) return true;
  final confirmed = await showDiscardTableEditsDialog(
    context: context,
    tableTitle: tableTitle,
    changeCount: buffer.changeCount,
  );
  return confirmed == true;
}

/// Prompt when leaving / refreshing a table that has uncommitted cell edits.
Future<bool?> showDiscardTableEditsDialog({
  required material.BuildContext context,
  required String tableTitle,
  required int changeCount,
}) {
  final n = changeCount;
  final noun = n == 1 ? 'change' : 'changes';
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) {
      return QueryaDialogCard(
        constraints: const material.BoxConstraints(maxWidth: 420),
        child: material.Padding(
          padding: const material.EdgeInsets.all(20),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              Text('Unsaved changes in "$tableTitle"').semiBold().large(),
              const Gap(8),
              Text(
                'This table has $n pending $noun that have not been saved. '
                'Continuing will discard them.',
              ).muted().small(),
              const Gap(20),
              material.Align(
                alignment: material.Alignment.centerRight,
                child: material.Wrap(
                  alignment: material.WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlineButton(
                      onPressed: () => material.Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    DestructiveButton(
                      onPressed: () => material.Navigator.of(ctx).pop(true),
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Throws unless a staged single-row DML statement matched exactly one row.
///
/// 0 rows means a stale key or concurrent delete; 2+ rows means an unkeyed
/// table has duplicates and the statement would silently rewrite all of them.
/// Callers run statements in a transaction, so throwing rolls the batch back.
void expectDmlMatchedRows(int affectedRows) {
  if (affectedRows == 1) return;
  if (affectedRows > 1) {
    throw StateError(
      'Save failed: a statement matched $affectedRows rows instead of 1. '
      'The table has duplicate rows or no unique key. '
      'No changes were applied.',
    );
  }
  throw StateError(
    'Save failed: a statement matched 0 rows. '
    'The row may have been changed or deleted. Refresh and try again.',
  );
}

/// Success toast after Save, e.g. `1 change saved`, `3 changes saved`.
String tableViewSavedMessage(int count) =>
    '$count ${count == 1 ? 'change' : 'changes'} saved';

/// Explains a failed Save in plain language; the raw error is one click away.
Future<void> showTableViewSaveFailedDialog({
  required material.BuildContext context,
  required Object error,
}) {
  final info = describeSaveError(error);
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => _SaveFailedDialog(info: info),
  );
}

class _SaveFailedDialog extends material.StatefulWidget {
  const _SaveFailedDialog({required this.info});

  final SaveErrorDescription info;

  @override
  material.State<_SaveFailedDialog> createState() => _SaveFailedDialogState();
}

class _SaveFailedDialogState extends material.State<_SaveFailedDialog> {
  bool _showDetails = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.info.details));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = widget.info;
    return QueryaDialogCard(
      constraints: const material.BoxConstraints(maxWidth: 480),
      child: material.Padding(
        padding: const material.EdgeInsets.all(20),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            material.Row(
              children: [
                material.Icon(
                  material.Icons.error_outline_rounded,
                  size: 20,
                  color: cs.destructive,
                ),
                const Gap(8),
                material.Expanded(child: Text(info.title).semiBold().large()),
              ],
            ),
            const Gap(10),
            Text(info.message).small(),
            if (info.hint != null) ...[
              const Gap(6),
              Text(info.hint!).muted().small(),
            ],
            const Gap(10),
            const Text('No changes were applied. Your edits are still pending.')
                .muted()
                .xSmall(),
            const Gap(12),
            material.InkWell(
              onTap: () => setState(() => _showDetails = !_showDetails),
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding: const material.EdgeInsets.symmetric(vertical: 4),
                child: material.Row(
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    material.Icon(
                      _showDetails
                          ? material.Icons.expand_less_rounded
                          : material.Icons.expand_more_rounded,
                      size: 16,
                      color: cs.mutedForeground,
                    ),
                    const Gap(4),
                    const Text('Details').muted().xSmall(),
                  ],
                ),
              ),
            ),
            if (_showDetails)
              material.Container(
                width: double.infinity,
                constraints: const material.BoxConstraints(maxHeight: 180),
                margin: const material.EdgeInsets.only(top: 6),
                padding: const material.EdgeInsets.all(10),
                decoration: material.BoxDecoration(
                  color: cs.muted.withValues(alpha: 0.4),
                  borderRadius: material.BorderRadius.circular(6),
                ),
                child: material.SingleChildScrollView(
                  child: material.SelectableText(
                    info.details,
                    style: material.TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.mutedForeground,
                    ),
                  ),
                ),
              ),
            const Gap(18),
            material.Row(
              mainAxisAlignment: material.MainAxisAlignment.end,
              children: [
                OutlineButton(
                  onPressed: _copy,
                  leading: material.Icon(
                    _copied
                        ? material.Icons.check_rounded
                        : material.Icons.copy_rounded,
                    size: 14,
                  ),
                  child: Text(_copied ? 'Copied' : 'Copy details'),
                ),
                const Gap(8),
                PrimaryButton(
                  onPressed: () => material.Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Result of [applyTableViewStagedChanges].
enum TableViewApplyStatus { noop, cancelled, applied, failed }

class TableViewApplyOutcome {
  const TableViewApplyOutcome._(this.status,
      {this.statementCount = 0, this.error});

  const TableViewApplyOutcome.noop() : this._(TableViewApplyStatus.noop);

  const TableViewApplyOutcome.cancelled()
      : this._(TableViewApplyStatus.cancelled);

  const TableViewApplyOutcome.applied(int statementCount)
      : this._(TableViewApplyStatus.applied, statementCount: statementCount);

  const TableViewApplyOutcome.failed(Object error)
      : this._(TableViewApplyStatus.failed, error: error);

  final TableViewApplyStatus status;
  final int statementCount;
  final Object? error;

  bool get isApplied => status == TableViewApplyStatus.applied;
  bool get isFailed => status == TableViewApplyStatus.failed;
}

/// Preview + execute a staging-buffer mutation plan for Table Browser.
///
/// [execute] must throw if any statement matched 0 rows (see
/// [expectDmlMatchedRows]) so this returns [TableViewApplyOutcome.failed]
/// and the caller keeps the staging buffer.
Future<TableViewApplyOutcome> applyTableViewStagedChanges({
  required material.BuildContext context,
  required DataGridStagingBuffer buffer,
  required SqlDialect dialect,
  required String tableName,
  String? schema,
  required List<String> primaryKeys,
  Map<String, String>? columnDataTypes,
  Map<String, TableColumnMeta>? columnMeta,
  required Future<void> Function(TableMutationPlan plan) execute,
}) async {
  if (!buffer.isDirty) return const TableViewApplyOutcome.noop();
  if (primaryKeys.isEmpty) {
    return const TableViewApplyOutcome.failed(
      'Cannot edit: no primary key detected',
    );
  }

  final plan = buffer.generateMutationPlan(
    dialect: dialect,
    tableName: tableName,
    schema: schema,
    primaryKeys: primaryKeys,
    columnDataTypes: columnDataTypes,
    columnMeta: columnMeta,
  );
  if (plan.isEmpty) return const TableViewApplyOutcome.noop();

  final confirmed = await showDmlPreviewDialog(context: context, plan: plan);
  if (confirmed != true) return const TableViewApplyOutcome.cancelled();
  if (!context.mounted) return const TableViewApplyOutcome.cancelled();

  try {
    await execute(plan);
    return TableViewApplyOutcome.applied(plan.statementCount);
  } catch (e) {
    return TableViewApplyOutcome.failed(e);
  }
}
