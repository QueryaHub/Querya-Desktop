import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

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
    final cs = Theme.of(context).colorScheme;

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
                          _ToolbarButton(
                            label: 'Add Row',
                            icon: material.Icons.add_rounded,
                            compact: compact,
                            tooltip: 'Add new row (Ctrl+Insert / Cmd+N)',
                            onPressed:
                                isSaving ? null : () => stagingBuffer.addRow(),
                          ),
                          const Gap(2),
                          _ToolbarButton(
                            label:
                                isSelectedDeleted ? 'Restore Row' : 'Delete Row',
                            icon: isSelectedDeleted
                                ? material.Icons.restore_from_trash_rounded
                                : material.Icons.remove_circle_outline_rounded,
                            compact: compact,
                            color: isSelectedDeleted
                                ? cs.primary
                                : (hasSelectedRow ? cs.destructive : null),
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
                      waitDuration: const Duration(milliseconds: 400),
                      child: compact
                          ? OutlineButton(
                              size: ButtonSize.small,
                              density: ButtonDensity.icon,
                              onPressed: isSaving
                                  ? null
                                  : () => stagingBuffer.revertAll(),
                              child: const material.Icon(
                                material.Icons.undo_rounded,
                                size: 14,
                              ),
                            )
                          : OutlineButton(
                              size: ButtonSize.small,
                              onPressed: isSaving
                                  ? null
                                  : () => stagingBuffer.revertAll(),
                              leading: const material.Icon(
                                material.Icons.undo_rounded,
                                size: 14,
                              ),
                              child: const Text('Revert All'),
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
                    waitDuration: const Duration(milliseconds: 400),
                    child: PrimaryButton(
                      size: ButtonSize.small,
                      onPressed: isDirty && !isSaving ? onApplyChanges : null,
                      leading: isSaving
                          ? material.SizedBox(
                              width: 12,
                              height: 12,
                              child: material.CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primaryForeground,
                              ),
                            )
                          : const material.Icon(
                              material.Icons.save_rounded,
                              size: 14,
                            ),
                      child: Text(
                        isSaving
                            ? 'Saving…'
                            : (compact ? 'Save' : 'Save Changes'),
                      ),
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
    final cs = Theme.of(context).colorScheme;
    final label = compact
        ? '$count'
        : '$count pending ${count == 1 ? 'change' : 'changes'}';
    return material.Tooltip(
      message: '$count pending ${count == 1 ? 'change' : 'changes'} not saved yet',
      waitDuration: const Duration(milliseconds: 400),
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

class _ToolbarButton extends material.StatefulWidget {
  const _ToolbarButton({
    required this.label,
    required this.icon,
    this.onPressed,
    this.color,
    this.tooltip,
    this.compact = false,
  });

  /// Icon only; the label moves into the tooltip.
  final bool compact;
  final String label;
  final material.IconData icon;
  final material.VoidCallback? onPressed;
  final material.Color? color;
  final String? tooltip;

  @override
  material.State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends material.State<_ToolbarButton> {
  bool _isHovered = false;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    final fg = widget.color ?? cs.foreground;

    material.Widget button = material.MouseRegion(
      cursor: enabled
          ? material.SystemMouseCursors.click
          : material.SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: enabled ? (_) => setState(() => _isHovered = false) : null,
      child: material.GestureDetector(
        onTap: widget.onPressed,
        behavior: material.HitTestBehavior.opaque,
        child: material.Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: material.AnimatedContainer(
            duration: context.motionDuration(QueryaMotion.fast),
            curve: context.motionCurve(QueryaMotion.enter),
            padding: const material.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: material.BoxDecoration(
              color: enabled && _isHovered
                  ? (widget.color != null
                      ? widget.color!.withValues(alpha: 0.12)
                      : cs.muted.withValues(alpha: 0.5))
                  : material.Colors.transparent,
              borderRadius: material.BorderRadius.circular(4),
            ),
            child: material.Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Icon(widget.icon, size: 14, color: fg),
                if (!widget.compact) ...[
                  const material.SizedBox(width: 4),
                  material.Text(
                    widget.label,
                    style: material.TextStyle(
                      fontSize: 12,
                      fontWeight: material.FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final tooltip = widget.compact
        ? '${widget.label}${widget.tooltip != null ? ' — ${widget.tooltip}' : ''}'
        : widget.tooltip;
    if (tooltip != null) {
      button = material.Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: button,
      );
    }

    return button;
  }
}
