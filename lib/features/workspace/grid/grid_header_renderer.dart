part of '../result_grid_view.dart';

class _HeaderRow extends material.StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.columnWidths,
    required this.window,
    required this.height,
    required this.colorScheme,
    this.sortColumnIndex,
    this.sortOrder,
    this.onSortColumn,
    this.onResizeColumn,
    this.onAutoFitColumn,
  });

  final List<String> columns;
  final List<double> columnWidths;
  final ResultGridColumnWindow window;
  final double height;
  final ColorScheme colorScheme;
  final int? sortColumnIndex;
  final ResultGridSortOrder? sortOrder;
  final material.ValueChanged<int>? onSortColumn;
  final void Function(int index, double delta)? onResizeColumn;
  final void Function(int index)? onAutoFitColumn;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      height: height,
      decoration: material.BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.35),
        border: material.Border(
          bottom: material.BorderSide(
            color: colorScheme.border.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: material.Row(
        children: [
          if (window.leadingWidth > 0)
            material.SizedBox(width: window.leadingWidth),
          for (var i = window.first; i <= window.last; i++)
            _HeaderCell(
              text: columns[i],
              width: columnWidths[i],
              colorScheme: colorScheme,
              sortOrder: sortColumnIndex == i ? sortOrder : null,
              onSort: onSortColumn != null ? () => onSortColumn!(i) : null,
              onResize: onResizeColumn != null
                  ? (delta) => onResizeColumn!(i, delta)
                  : null,
              onAutoFit:
                  onAutoFitColumn != null ? () => onAutoFitColumn!(i) : null,
            ),
          if (window.trailingWidth > 0)
            material.SizedBox(width: window.trailingWidth),
        ],
      ),
    );
  }
}

class _HeaderCell extends material.StatelessWidget {
  const _HeaderCell({
    required this.text,
    required this.width,
    required this.colorScheme,
    this.sortOrder,
    this.onSort,
    this.onResize,
    this.onAutoFit,
  });

  final String text;
  final double width;
  final ColorScheme colorScheme;
  final ResultGridSortOrder? sortOrder;
  final material.VoidCallback? onSort;
  final material.ValueChanged<double>? onResize;
  final material.VoidCallback? onAutoFit;

  @override
  material.Widget build(material.BuildContext context) {
    final isSorted = sortOrder != null;
    final style = material.TextStyle(
      fontSize: 12,
      fontWeight: material.FontWeight.w600,
      color: isSorted ? colorScheme.primary : colorScheme.foreground,
    );

    return material.Container(
      width: width,
      height: double.infinity,
      decoration: material.BoxDecoration(
        border: material.Border(
          right: material.BorderSide(
            color: colorScheme.border.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: material.Stack(
        clipBehavior: material.Clip.none,
        children: [
          material.Positioned.fill(
            child: material.MouseRegion(
              cursor: onSort != null
                  ? material.SystemMouseCursors.click
                  : material.SystemMouseCursors.basic,
              child: material.GestureDetector(
                behavior: material.HitTestBehavior.opaque,
                onTap: onSort,
                child: material.Padding(
                  padding: const material.EdgeInsets.symmetric(horizontal: 10),
                  child: material.Row(
                    children: [
                      material.Expanded(
                        child: material.Tooltip(
                          message: text,
                          waitDuration: kQueryaTooltipWait,
                          child: material.Text(
                            text,
                            style: style,
                            overflow: material.TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                      if (sortOrder != null) ...[
                        const Gap(4),
                        material.AnimatedRotation(
                          turns: sortOrder == ResultGridSortOrder.ascending
                              ? 0.0
                              : 0.5,
                          duration: context.motionDuration(QueryaMotion.fast),
                          curve: context.motionCurve(QueryaMotion.enter),
                          child: material.Icon(
                            material.Icons.arrow_upward_rounded,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onResize != null || onAutoFit != null)
            material.Positioned(
              right: -5,
              top: 0,
              bottom: 0,
              width: 12,
              child: material.MouseRegion(
                cursor: material.SystemMouseCursors.resizeColumn,
                child: material.GestureDetector(
                  behavior: material.HitTestBehavior.translucent,
                  onDoubleTap: onAutoFit,
                  onHorizontalDragUpdate: onResize != null
                      ? (details) => onResize!(details.delta.dx)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
