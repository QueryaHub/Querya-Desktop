import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/features/workspace/grid_selection_calc_engine.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Status bar footer for Data Grid displaying live selection statistics (Count, Distinct, Sum, Avg, Median, Min, Max).
class DataGridCalcBar extends StatelessWidget {
  const DataGridCalcBar({
    super.key,
    required this.stats,
  });

  final GridCalcStats stats;

  @override
  Widget build(BuildContext context) {
    final visible = stats.totalCount > 1 || stats.hasNumericStats;
    final cs = Theme.of(context).colorScheme;
    final duration = context.motionDuration(QueryaMotion.fast);
    final curve = context.motionCurve(QueryaMotion.enter);

    return AnimatedContainer(
      duration: duration,
      curve: curve,
      height: visible ? 26 : 0,
      clipBehavior: Clip.hardEdge,
      padding: const material.EdgeInsets.symmetric(horizontal: 10),
      decoration: material.BoxDecoration(
        color: cs.card,
        border: material.Border(
          top: material.BorderSide(
            color: cs.border.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: material.Row(
        children: [
          material.Expanded(
            child: material.SingleChildScrollView(
              scrollDirection: material.Axis.horizontal,
              child: material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  _StatBadge(
                    label: 'Count',
                    value: '${stats.totalCount}',
                  ),
                  const Gap(8),
                  _StatBadge(
                    label: 'Distinct',
                    value: '${stats.distinctCount}',
                  ),
                  if (stats.nullCount > 0) ...[
                    const Gap(8),
                    _StatBadge(
                      label: 'NULLs',
                      value: '${stats.nullCount}',
                    ),
                  ],
                  if (stats.hasNumericStats) ...[
                    const Gap(8),
                    _StatBadge(
                      label: 'Sum',
                      value: GridSelectionCalcEngine.formatNum(stats.sum),
                    ),
                    const Gap(8),
                    _StatBadge(
                      label: 'Avg',
                      value: GridSelectionCalcEngine.formatNum(stats.average),
                    ),
                    if (stats.median != null) ...[
                      const Gap(8),
                      _StatBadge(
                        label: 'Median',
                        value: GridSelectionCalcEngine.formatNum(stats.median),
                      ),
                    ],
                    const Gap(8),
                    _StatBadge(
                      label: 'Min',
                      value: GridSelectionCalcEngine.formatNum(stats.min),
                    ),
                    const Gap(8),
                    _StatBadge(
                      label: 'Max',
                      value: GridSelectionCalcEngine.formatNum(stats.max),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Gap(6),
          material.Tooltip(
            message: 'Copy all stats summary',
            child: material.InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: stats.toSummaryString()));
              },
              borderRadius: material.BorderRadius.circular(3),
              child: material.Padding(
                padding: const material.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: material.Row(
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    material.Icon(
                      material.Icons.copy_all_rounded,
                      size: 13,
                      color: cs.mutedForeground,
                    ),
                    const Gap(3),
                    Text('Copy Stats', style: TextStyle(fontSize: 10.5, color: cs.mutedForeground)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return material.Tooltip(
      message: 'Click to copy $label: $value',
      child: material.InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
        },
        borderRadius: material.BorderRadius.circular(3),
        child: material.Padding(
          padding: const material.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: material.Row(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              Text(
                '$label: ',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.mutedForeground,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.foreground,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
