import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Opens a confirmation dialog when destructive SQL statements (DROP, TRUNCATE, etc.)
/// are detected before execution.
///
/// Returns `true` if the user confirmed execution, or `false`/`null` if cancelled.
Future<bool?> showDestructiveQueryDialog({
  required material.BuildContext context,
  required DestructiveSqlInspectionResult result,
  required String sql,
  String? connectionName,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) => _DestructiveQueryDialog(
      result: result,
      sql: sql,
      connectionName: connectionName,
    ),
  );
}

class _DestructiveQueryDialog extends material.StatefulWidget {
  const _DestructiveQueryDialog({
    required this.result,
    required this.sql,
    this.connectionName,
  });

  final DestructiveSqlInspectionResult result;
  final String sql;
  final String? connectionName;

  @override
  material.State<_DestructiveQueryDialog> createState() =>
      _DestructiveQueryDialogState();
}

class _DestructiveQueryDialogState extends material.State<_DestructiveQueryDialog> {
  bool _acknowledged = false;
  bool _copied = false;

  Future<void> _copySql() async {
    await Clipboard.setData(ClipboardData(text: widget.sql));
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
    final isCritical = widget.result.maxRiskLevel == 'CRITICAL';

    return QueryaDialogCard(
      borderColor: cs.destructive.withValues(alpha: isDark ? 0.6 : 0.4),
      constraints: const material.BoxConstraints(
        minWidth: 540,
        maxWidth: 680,
        minHeight: 440,
        maxHeight: 580,
      ),
      child: material.FocusTraversalGroup(
          child: material.SizedBox(
            height: 540,
            child: material.Padding(
              padding: const material.EdgeInsets.all(20),
              child: material.Column(
                mainAxisSize: material.MainAxisSize.min,
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                // Header
                material.Row(
                  children: [
                    material.Container(
                      padding: const material.EdgeInsets.all(8),
                      decoration: material.BoxDecoration(
                        color: cs.destructive.withValues(alpha: 0.15),
                        borderRadius: material.BorderRadius.circular(8),
                      ),
                      child: material.Icon(
                        material.Icons.warning_amber_rounded,
                        size: 24,
                        color: cs.destructive,
                      ),
                    ),
                    const Gap(12),
                    material.Expanded(
                      child: material.Column(
                        crossAxisAlignment: material.CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCritical
                                ? 'Critical Destructive Operation'
                                : 'Destructive Operation Detected',
                          ).semiBold().large(),
                          const Gap(2),
                          if (widget.connectionName != null)
                            Text(
                              'Target connection: ${widget.connectionName}',
                            ).muted().small()
                          else
                            const Text(
                              'This statement will permanently alter or delete database objects.',
                            ).muted().small(),
                        ],
                      ),
                    ),
                  ],
                ),
                const Gap(16),

                // Detected operations list
                material.Container(
                  padding: const material.EdgeInsets.all(12),
                  decoration: material.BoxDecoration(
                    color: cs.destructive.withValues(
                      alpha: isDark ? 0.12 : 0.06,
                    ),
                    borderRadius: material.BorderRadius.circular(8),
                    border: material.Border.all(
                      color: cs.destructive.withValues(
                        alpha: isDark ? 0.35 : 0.25,
                      ),
                    ),
                  ),
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    children: [
                      for (final op in widget.result.operations) ...[
                        material.Row(
                          crossAxisAlignment: material.CrossAxisAlignment.start,
                          children: [
                            material.Container(
                              padding: const material.EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: material.BoxDecoration(
                                color: cs.destructive,
                                borderRadius: material.BorderRadius.circular(4),
                              ),
                              child: Text(
                                op.type.label,
                                style: const TextStyle(
                                  color: material.Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Gap(8),
                            material.Expanded(
                              child: Text(
                                op.description,
                                style: material.TextStyle(
                                  fontSize: 12,
                                  color: cs.foreground,
                                  fontWeight: material.FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (op != widget.result.operations.last) const Gap(8),
                      ],
                    ],
                  ),
                ),
                const Gap(14),

                // SQL Script Preview Header
                material.Row(
                  mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('QUERY PREVIEW').semiBold().xSmall().muted(),
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

                // SQL Code block container
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
                        widget.sql,
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
                const Gap(14),

                // Confirmation Checkbox
                material.Row(
                  children: [
                    material.Checkbox(
                      value: _acknowledged,
                      onChanged: (v) => setState(() => _acknowledged = v ?? false),
                    ),
                    const Gap(8),
                    material.Expanded(
                      child: material.GestureDetector(
                        onTap: () => setState(() => _acknowledged = !_acknowledged),
                        child: const Text(
                          'I understand that this query cannot be undone and may result in permanent data loss.',
                        ).small(),
                      ),
                    ),
                  ],
                ),
                const Gap(16),

                // Action buttons
                material.FocusTraversalGroup(
                  policy: material.WidgetOrderTraversalPolicy(),
                  child: material.Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: material.WrapAlignment.end,
                    crossAxisAlignment: material.WrapCrossAlignment.center,
                    children: [
                      GhostButton(
                        onPressed: () => material.Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      DestructiveButton(
                        onPressed: _acknowledged
                            ? () => material.Navigator.of(context).pop(true)
                            : null,
                        leading: const material.Icon(
                          material.Icons.delete_forever_rounded,
                          size: 16,
                        ),
                        child: const Text('Execute Destructive Statement'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
