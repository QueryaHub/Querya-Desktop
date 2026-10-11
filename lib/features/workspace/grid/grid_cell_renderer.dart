part of '../result_grid_view.dart';

class _GridCell extends material.StatelessWidget {
  const _GridCell({
    super.key,
    required this.row,
    required this.column,
    this.columnName = '',
    required this.text,
    required this.width,
    required this.colorScheme,
    required this.striped,
    this.rowStatus = StagedRowStatus.unchanged,
    this.cellStatus = StagedCellStatus.clean,
    this.isSelected = false,
    this.isEditing = false,
    this.isSelectionTop = false,
    this.isSelectionBottom = false,
    this.isSelectionLeft = false,
    this.isSelectionRight = false,
    this.dataTypeName,
    this.onCommitEdit,
    this.onCancelEdit,
    this.onOpenInspector,
  });

  final int row;
  final int column;
  final String columnName;
  final String text;
  final double width;
  final ColorScheme colorScheme;
  final bool striped;
  final StagedRowStatus rowStatus;
  final StagedCellStatus cellStatus;
  final bool isSelected;
  final bool isEditing;
  final bool isSelectionTop;
  final bool isSelectionBottom;
  final bool isSelectionLeft;
  final bool isSelectionRight;
  final String? dataTypeName;
  final void Function(
    int row,
    int col,
    String val, {
    bool moveNextCol,
    bool movePrevCol,
    bool moveNextRow,
    bool movePrevRow,
  })? onCommitEdit;
  final material.VoidCallback? onCancelEdit;
  final void Function(int row, int col)? onOpenInspector;

  /// True when [other] would draw exactly the same cell (see [_DataRow.sameAs]):
  /// scrolling the column window keeps the cells that stay visible untouched.
  bool sameAs(_GridCell other) =>
      identical(this, other) ||
      row == other.row &&
          column == other.column &&
          columnName == other.columnName &&
          text == other.text &&
          width == other.width &&
          colorScheme == other.colorScheme &&
          striped == other.striped &&
          rowStatus == other.rowStatus &&
          cellStatus == other.cellStatus &&
          isSelected == other.isSelected &&
          isEditing == other.isEditing &&
          isSelectionTop == other.isSelectionTop &&
          isSelectionBottom == other.isSelectionBottom &&
          isSelectionLeft == other.isSelectionLeft &&
          isSelectionRight == other.isSelectionRight &&
          dataTypeName == other.dataTypeName &&
          onCommitEdit == other.onCommitEdit &&
          onCancelEdit == other.onCancelEdit &&
          onOpenInspector == other.onOpenInspector;

  @override
  material.Widget build(material.BuildContext context) {
    if (isEditing) {
      return GridCellEditor(
        initialValue: text,
        width: width,
        height: double.infinity,
        dataTypeName: dataTypeName,
        onCommit: (val,
            {moveNextCol = false,
            movePrevCol = false,
            moveNextRow = false,
            movePrevRow = false}) {
          onCommitEdit?.call(
            row,
            column,
            val,
            moveNextCol: moveNextCol,
            movePrevCol: movePrevCol,
            moveNextRow: moveNextRow,
            movePrevRow: movePrevRow,
          );
        },
        onCancel: () => onCancelEdit?.call(),
        onOpenInspector: () => onOpenInspector?.call(row, column),
      );
    }

    final isNull = text == 'NULL';
    final isDeleted = rowStatus == StagedRowStatus.deleted;
    final isInserted = rowStatus == StagedRowStatus.inserted;
    final isModified = cellStatus == StagedCellStatus.modified;

    final style = material.TextStyle(
      fontSize: 12,
      fontWeight: material.FontWeight.normal,
      fontFamily: 'monospace',
      color: isDeleted
          ? colorScheme.destructive.withValues(alpha: 0.7)
          : (isNull
              ? colorScheme.mutedForeground.withValues(alpha: 0.5)
              : colorScheme.foreground),
      decoration: isDeleted ? material.TextDecoration.lineThrough : null,
      fontStyle: isNull ? material.FontStyle.italic : material.FontStyle.normal,
    );

    final bg = isSelected
        ? colorScheme.primary.withValues(alpha: 0.18)
        : (isDeleted
            ? colorScheme.destructive.withValues(alpha: 0.08)
            : (isModified
                ? colorScheme.primary.withValues(alpha: 0.14)
                : (isInserted
                    ? colorScheme.primary.withValues(alpha: 0.08)
                    : (striped
                        ? colorScheme.muted.withValues(alpha: 0.12)
                        : material.Colors.transparent))));

    // Primary/secondary gestures and hover tooltips are hoisted to the grid
    // level (#983, #1346). _GridCell is now a pure lightweight leaf widget
    // without per-cell ContextMenu, Listener, or Tooltip.
    return material.Container(
      width: width,
      height: double.infinity,
      padding: const material.EdgeInsets.symmetric(horizontal: 10),
      alignment: material.Alignment.centerLeft,
      decoration: material.BoxDecoration(
        color: bg,
        border: material.Border(
          right: material.BorderSide(
            color: isSelectionRight
                ? colorScheme.primary
                : colorScheme.border.withValues(alpha: 0.3),
            width: isSelectionRight ? 1.5 : 1.0,
          ),
          left: isSelectionLeft
              ? material.BorderSide(color: colorScheme.primary, width: 1.5)
              : material.BorderSide.none,
          top: isSelectionTop
              ? material.BorderSide(color: colorScheme.primary, width: 1.5)
              : material.BorderSide.none,
          bottom: isSelectionBottom
              ? material.BorderSide(color: colorScheme.primary, width: 1.5)
              : material.BorderSide(
                  color: colorScheme.border.withValues(alpha: 0.15),
                ),
        ),
      ),
      child: material.Stack(
        clipBehavior: material.Clip.none,
        alignment: material.Alignment.centerLeft,
        children: [
          material.Text(
            text,
            style: style,
            overflow: material.TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (isModified)
            material.Positioned(
              top: -8,
              right: -8,
              child: material.CustomPaint(
                size: const material.Size(6, 6),
                painter: _TriangleCornerPainter(color: colorScheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _TriangleCornerPainter extends material.CustomPainter {
  const _TriangleCornerPainter({required this.color});
  final material.Color color;

  @override
  void paint(material.Canvas canvas, material.Size size) {
    final paint = material.Paint()..color = color;
    final path = material.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TriangleCornerPainter oldDelegate) =>
      oldDelegate.color != color;
}
