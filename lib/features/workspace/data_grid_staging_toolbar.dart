import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/ui/querya_tooltip.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Toolbar for managing staged data changes (Add, Delete, Revert, Save).
class DataGridStagingToolbar extends StatelessWidget {
  const DataGridStagingToolbar({
    super.key,
    required this.stagingBuffer,
    this.selectedRowIndex,
    this.onApplyChanges,
    this.isSaving = false,
  });

  final DataGridStagingBuffer stagingBuffer;
  final int? selectedRowIndex;
  final VoidCallback? onApplyChanges;
  final bool isSaving;

  /// Below this width row actions collapse to icons (tooltips keep the names).
  static const double compactWidth = 620;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return ListenableBuilder(
      listenable: stagingBuffer,
      builder: (context, _) {
        final isDirty = stagingBuffer.isDirty;
        final changeCount = stagingBuffer.changeCount;
        final selectedRow = selectedRowIndex;
        final hasSelectedRow = selectedRow != null &&
            selectedRow >= 0 &&
            selectedRow < stagingBuffer.totalRowCount;
        final isSelectedDeleted = hasSelectedRow &&
            stagingBuffer.getRowStatus(selectedRow) == StagedRowStatus.deleted;

        return material.Container(
          height: 38,
          padding: const material.EdgeInsets.only(left: 6, right: 8),
          decoration: material.BoxDecoration(
            color: cs.card,
            border: material.Border(
              bottom: material.BorderSide(
                color: cs.border.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
          ),
          child: material.LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < compactWidth;
              return material.Row(
                children: [
                  // Row actions: may scroll when space is tight.
                  material.Expanded(
                    child: material.SingleChildScrollView(
                      scrollDirection: material.Axis.horizontal,
                      child: material.Row(
                        mainAxisSize: material.MainAxisSize.min,
                        children: [
                          QueryaButton.ghost(
                            label: 'Add Row',
                            icon: material.Icons.add_rounded,
                            compact: compact,
                            size: QueryaControlSize.sm,
                            tone: QueryaButtonTone.normal,
                            tooltip: 'Add new row (Ctrl+Insert / Cmd+N)',
                            onPressed: isSaving ? null : () => stagingBuffer.addRow(),
                          ),
                          const Gap(2),
                          QueryaButton.ghost(
                            label: isSelectedDeleted ? 'Restore Row' : 'Delete Row',
                            icon: isSelectedDeleted
                                ? material.Icons.restore_from_trash_rounded
                                : material.Icons.remove_circle_outline_rounded,
                            compact: compact,
                            size: QueryaControlSize.sm,
                            tone: isSelectedDeleted || !hasSelectedRow
                                ? QueryaButtonTone.normal
                                : QueryaButtonTone.destructive,
                            tooltip: isSelectedDeleted
                                ? 'Restore marked row'
                                : hasSelectedRow
                                    ? 'Mark row for deletion (Ctrl+Delete / Cmd+Backspace)'
                                    : 'Select a row to delete it',
                            onPressed: isSaving || !hasSelectedRow
                                ? null
                                : () =>
                                    stagingBuffer.toggleDeleteRow(selectedRow),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Gap(8),
                  // Commit area: always visible on the right.
                  if (isDirty) ...[
                    _PendingBadge(count: changeCount, compact: compact),
                    const Gap(6),
                    material.Tooltip(
                      message: 'Discard all pending edits (Ctrl+Z / Cmd+Z)',
                      waitDuration: kQueryaTooltipWait,
                      child: compact
                          ? QueryaButton.icon(
                            icon: material.Icons.undo_rounded,
                            tooltip: 'Revert All',
                            size: QueryaControlSize.sm,
                            onPressed: isSaving ? null : () => stagingBuffer.revertAll(),
                          )
                          : QueryaButton.secondary(
                            label: 'Revert All',
                            icon: material.Icons.undo_rounded,
                            onPressed: isSaving
                                  ? null
                                  : () => stagingBuffer.revertAll(),
                            size: QueryaControlSize.sm,
                          ),
                    ),
                  ] else
                    material.Row(
                      mainAxisSize: material.MainAxisSize.min,
                      children: [
                        material.Icon(
                          material.Icons.check_circle_outline_rounded,
                          size: 13,
                          color: cs.mutedForeground,
                        ),
                        const Gap(4),
                        const Text('No changes').xSmall().muted(),
                      ],
                    ),
                  const Gap(6),
                  material.Tooltip(
                    message: isDirty
                        ? 'Review and save pending changes (Ctrl+S / Cmd+S)'
                        : 'No pending changes to save',
                    waitDuration: kQueryaTooltipWait,
                    child: QueryaButton.primary(
                      label: isSaving ? 'Saving…' : (compact ? 'Save' : 'Save Changes'),
                      icon: material.Icons.save_rounded,
                      loading: isSaving,
                      onPressed: isDirty && !isSaving ? onApplyChanges : null,
                      size: QueryaControlSize.sm,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _PendingBadge extends StatelessWidget {
  const _PendingBadge({required this.count, required this.compact});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final label = compact
        ? '$count'
        : '$count pending ${count == 1 ? 'change' : 'changes'}';
    return material.Tooltip(
      message: '$count pending ${count == 1 ? 'change' : 'changes'} not saved yet',
      waitDuration: kQueryaTooltipWait,
      child: material.Container(
        padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: material.BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          borderRadius: material.BorderRadius.circular(10),
          border: material.Border.all(
            color: cs.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Container(
              width: 5,
              height: 5,
              decoration: material.BoxDecoration(
                color: cs.primary,
                shape: material.BoxShape.circle,
              ),
            ),
            const Gap(5),
            Text(label).xSmall().semiBold(),
          ],
        ),
      ),
    );
  }
}
