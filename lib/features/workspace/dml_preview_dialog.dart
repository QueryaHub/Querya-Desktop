import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Opens the DML Preview and Confirmation dialog before executing staged changes.
///
/// Returns `true` if user confirmed execution, or `false`/`null` if cancelled.
Future<bool?> showDmlPreviewDialog({
  required material.BuildContext context,
  required TableMutationPlan plan,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) => _DmlPreviewDialog(plan: plan),
  );
}

class _DmlPreviewDialog extends material.StatefulWidget {
  const _DmlPreviewDialog({required this.plan});

  final TableMutationPlan plan;

  @override
  material.State<_DmlPreviewDialog> createState() => _DmlPreviewDialogState();
}

class _DmlPreviewDialogState extends material.State<_DmlPreviewDialog> {
  bool _copied = false;

  int get _updateCount =>
      widget.plan.statements.where((s) => s.type == MutationType.update).length;

  int get _insertCount =>
      widget.plan.statements.where((s) => s.type == MutationType.insert).length;

  int get _deleteCount =>
      widget.plan.statements.where((s) => s.type == MutationType.delete).length;

  String get _dialectName {
    switch (widget.plan.dialect) {
      case SqlDialect.postgres:
        return 'PostgreSQL';
      case SqlDialect.mysql:
        return 'MySQL';
      case SqlDialect.sqlite:
        return 'SQLite';
    }
  }

  Future<void> _copySql() async {
    final sql = widget.plan.toTransactionSql();
    await Clipboard.setData(ClipboardData(text: sql));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final sql = widget.plan.toTransactionSql();

    return QueryaDialogCard(
      constraints: const material.BoxConstraints(
        minWidth: 560,
        maxWidth: 720,
        minHeight: 380,
        maxHeight: 580,
      ),
      child: material.FocusTraversalGroup(
          child: material.Padding(
          padding: const material.EdgeInsets.all(18),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            children: [
              // Header Row
              material.Row(
                children: [
                  material.Icon(
                    material.Icons.save_as_rounded,
                    size: 20,
                    color: cs.primary,
                  ),
                  const Gap(8),
                  const Text('Confirm Data Changes').semiBold().large(),
                ],
              ),
              const Gap(4),
              const Text(
                'Review pending SQL mutations before applying them to the database.',
              ).muted().small(),
              const Gap(14),

              // Metadata badges row
              material.Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: material.WrapCrossAlignment.center,
                children: [
                  // Target Table Badge
                  material.Container(
                    padding: const material.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: material.BoxDecoration(
                      color: cs.muted,
                      borderRadius: material.BorderRadius.circular(6),
                    ),
                    child: material.Row(
                      mainAxisSize: material.MainAxisSize.min,
                      children: [
                        material.Icon(
                          material.Icons.table_chart_outlined,
                          size: 14,
                          color: cs.foreground,
                        ),
                        const Gap(6),
                        Text(
                          widget.plan.schema != null &&
                                  widget.plan.schema!.isNotEmpty
                              ? '${widget.plan.schema}.${widget.plan.tableName}'
                              : widget.plan.tableName,
                        ).semiBold().small(),
                      ],
                    ),
                  ),

                  // Dialect Badge
                  material.Container(
                    padding: const material.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: material.BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: material.BorderRadius.circular(6),
                      border: material.Border.all(
                        color: cs.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _dialectName,
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  // Changes Breakdown Pills
                  if (_updateCount > 0)
                    _buildCountPill(
                      label: '$_updateCount UPDATE',
                      color: material.Colors.amber.shade700,
                      isDark: isDark,
                    ),
                  if (_insertCount > 0)
                    _buildCountPill(
                      label: '$_insertCount INSERT',
                      color: material.Colors.green.shade600,
                      isDark: isDark,
                    ),
                  if (_deleteCount > 0)
                    _buildCountPill(
                      label: '$_deleteCount DELETE',
                      color: material.Colors.red.shade600,
                      isDark: isDark,
                    ),
                ],
              ),

              // Warning banner if table lacks primary key and performs UPDATE/DELETE
              if (!widget.plan.hasPrimaryKey &&
                  widget.plan.statements.any(
                    (s) =>
                        s.type == MutationType.update ||
                        s.type == MutationType.delete,
                  )) ...[
                const Gap(10),
                material.Container(
                  padding: const material.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: material.BoxDecoration(
                    color: material.Colors.amber.withValues(
                      alpha: isDark ? 0.15 : 0.08,
                    ),
                    borderRadius: material.BorderRadius.circular(6),
                    border: material.Border.all(
                      color: material.Colors.amber.withValues(alpha: 0.4),
                    ),
                  ),
                  child: material.Row(
                    children: [
                      material.Icon(
                        material.Icons.warning_amber_rounded,
                        size: 15,
                        color: material.Colors.amber.shade700,
                      ),
                      const Gap(8),
                      material.Expanded(
                        child: const Text(
                          'No Primary Key detected. WHERE clauses compare all columns (identical duplicate rows will be modified together).',
                        ).xSmall().muted(),
                      ),
                    ],
                  ),
                ),
              ],
              const Gap(14),

              // SQL Preview code block header
              material.Row(
                mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TRANSACTION SCRIPT').semiBold().xSmall(),
                  material.InkWell(
                    onTap: _copySql,
                    borderRadius: material.BorderRadius.circular(4),
                    child: material.Padding(
                      padding: const material.EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: material.Row(
                        mainAxisSize: material.MainAxisSize.min,
                        children: [
                          material.Icon(
                            _copied
                                ? material.Icons.check_rounded
                                : material.Icons.copy_rounded,
                            size: 13,
                            color: _copied
                                ? material.Colors.green
                                : cs.mutedForeground,
                          ),
                          const Gap(4),
                          Text(_copied ? 'Copied' : 'Copy SQL').xSmall(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(6),

              // SQL Code Preview Container
              material.Expanded(
                child: material.Container(
                  padding: const material.EdgeInsets.all(12),
                  decoration: material.BoxDecoration(
                    color: isDark
                        ? const material.Color(0xFF141416)
                        : const material.Color(0xFFF4F4F6),
                    borderRadius: material.BorderRadius.circular(8),
                    border: material.Border.all(
                      color: cs.border.withValues(alpha: 0.6),
                    ),
                  ),
                  child: material.SingleChildScrollView(
                    child: material.SelectableText(
                      sql,
                      style: material.TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.45,
                        color: isDark
                            ? const material.Color(0xFFE2E8F0)
                            : const material.Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ),
              ),
              const Gap(12),

              // Atomic Notice
              material.Container(
                padding: const material.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: material.BoxDecoration(
                  color: cs.muted.withValues(alpha: 0.4),
                  borderRadius: material.BorderRadius.circular(6),
                ),
                child: material.Row(
                  children: [
                    material.Icon(
                      material.Icons.info_outline,
                      size: 15,
                      color: cs.mutedForeground,
                    ),
                    const Gap(8),
                    const material.Expanded(
                      child: Text(
                        'All mutations will be executed atomically in a single transaction.',
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(16),

              // Actions
              material.Row(
                mainAxisAlignment: material.MainAxisAlignment.end,
                children: [
                  OutlineButton(
                    onPressed: () => material.Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const Gap(8),
                  PrimaryButton(
                    onPressed: () => material.Navigator.of(context).pop(true),
                    leading: const material.Icon(
                      material.Icons.save_outlined,
                      size: 16,
                    ),
                    child: const Text('Apply Changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  material.Widget _buildCountPill({
    required String label,
    required material.Color color,
    required bool isDark,
  }) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: material.BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(
          color: color.withValues(alpha: isDark ? 0.45 : 0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}
