part of '../result_grid_view.dart';

class _GridCell extends material.StatelessWidget {
  const _GridCell({
    super.key,
    required this.row,
    required this.column,
    this.columnName = '',
    required this.text,
    required this.width,
    required this.colors,
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
  final QueryaUiColors colors;
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
          colors == other.colors &&
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

    final style = _CellLook.style(
      colors,
      isNull: isNull,
      isDeleted: isDeleted,
    );
    final decoration = _CellLook.decoration(
      colors,
      background: isSelected
          ? _CellBackground.selected
          : (isDeleted
              ? _CellBackground.deleted
              : (isModified
                  ? _CellBackground.modified
                  : (isInserted
                      ? _CellBackground.inserted
                      : (striped
                          ? _CellBackground.striped
                          : _CellBackground.none)))),
      right: isSelectionRight,
      left: isSelectionLeft,
      top: isSelectionTop,
      bottom: isSelectionBottom,
    );

    // Primary/secondary gestures and hover tooltips are hoisted to the grid
    // level (#983, #1346). _GridCell is a lightweight leaf widget.
    // ExcludeSemantics prevents redundant per-cell Text semantics nodes,
    // preserving the single row semantics label per row (#981).
    return material.ExcludeSemantics(
      child: material.Container(
      width: width,
      height: double.infinity,
      padding: const material.EdgeInsets.symmetric(horizontal: 10),
      alignment: material.Alignment.centerLeft,
      decoration: decoration,
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
                painter: _TriangleCornerPainter(color: colors.primary),
              ),
            ),
        ],
      ),
    ),
    );
  }
}

enum _CellBackground { selected, deleted, modified, inserted, striped, none }

/// The looks a cell can have are few, so each is built once per colour scheme
/// and shared (#1519): a scroll that builds a new row reuses them instead of
/// allocating a style, a decoration, a border and four sides per cell.
abstract final class _CellLook {
  static QueryaUiColors? _scheme;
  static final _styles = List<material.TextStyle?>.filled(4, null);
  static final _decorations = <int, material.BoxDecoration>{};

  /// A new colour scheme (theme switch) drops what was built for the old one.
  static void _forget(QueryaUiColors scheme) {
    if (identical(_scheme, scheme)) return;
    _scheme = scheme;
    _styles.fillRange(0, _styles.length, null);
    _decorations.clear();
  }

  static material.TextStyle style(
    QueryaUiColors scheme, {
    required bool isNull,
    required bool isDeleted,
  }) {
    _forget(scheme);
    final key = (isNull ? 1 : 0) | (isDeleted ? 2 : 0);
    return _styles[key] ??= material.TextStyle(
      fontSize: 12,
      fontWeight: material.FontWeight.normal,
      fontFamily: 'monospace',
      // Without a CJK family the engine searches for a fallback per paragraph
      // and is ~40x slower on CJK text (#1553).
      fontFamilyFallback: QueryaTypography.cjkFontFamilyFallback,
      color: isDeleted
          ? scheme.destructive.withValues(alpha: 0.7)
          : (isNull
              ? scheme.mutedForeground.withValues(alpha: 0.5)
              : scheme.foreground),
      decoration: isDeleted ? material.TextDecoration.lineThrough : null,
      fontStyle: isNull ? material.FontStyle.italic : material.FontStyle.normal,
    );
  }

  static material.BoxDecoration decoration(
    QueryaUiColors scheme, {
    required _CellBackground background,
    required bool right,
    required bool left,
    required bool top,
    required bool bottom,
  }) {
    _forget(scheme);
    final key = background.index |
        (right ? 1 << 3 : 0) |
        (left ? 1 << 4 : 0) |
        (top ? 1 << 5 : 0) |
        (bottom ? 1 << 6 : 0);
    return _decorations[key] ??= material.BoxDecoration(
      color: switch (background) {
        _CellBackground.selected => scheme.primary.withValues(alpha: 0.18),
        _CellBackground.deleted => scheme.destructive.withValues(alpha: 0.08),
        _CellBackground.modified => scheme.primary.withValues(alpha: 0.14),
        _CellBackground.inserted => scheme.primary.withValues(alpha: 0.08),
        _CellBackground.striped => scheme.muted.withValues(alpha: 0.12),
        _CellBackground.none => material.Colors.transparent,
      },
      border: material.Border(
        right: material.BorderSide(
          color: right
              ? scheme.primary
              : scheme.border.withValues(alpha: 0.3),
          width: right ? 1.5 : 1.0,
        ),
        left: left
            ? material.BorderSide(color: scheme.primary, width: 1.5)
            : material.BorderSide.none,
        top: top
            ? material.BorderSide(color: scheme.primary, width: 1.5)
            : material.BorderSide.none,
        bottom: bottom
            ? material.BorderSide(color: scheme.primary, width: 1.5)
            : material.BorderSide(
                color: scheme.border.withValues(alpha: 0.15),
              ),
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
