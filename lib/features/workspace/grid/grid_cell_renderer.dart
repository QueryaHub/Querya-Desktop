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
    this.canFilter = false,
    this.hasStagingBuffer = false,
    this.dataTypeName,
    this.onSecondaryTap,
    this.onCommitEdit,
    this.onCancelEdit,
    this.onOpenInspector,
    this.onCopyCell,
    this.onFilterByValue,
    this.onFilterComparison,
    this.onSetNull,
    this.onSetEmpty,
    this.onRevertCell,
    this.onDuplicateRow,
    this.onToggleDeleteRow,
    this.onRevertRow,
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
  final bool canFilter;
  final bool hasStagingBuffer;
  final String? dataTypeName;
  final void Function(int row, int col)? onSecondaryTap;
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
  final void Function(
    int row,
    int col, {
    bool withHeaders,
    bool asJson,
    bool asCsv,
  })? onCopyCell;
  final void Function(int row, int col, {required bool invert})?
      onFilterByValue;
  final void Function(int row, int col, String operator)? onFilterComparison;
  final void Function(int row, int col)? onSetNull;
  final void Function(int row, int col)? onSetEmpty;
  final void Function(int row, int col)? onRevertCell;
  final void Function(int row)? onDuplicateRow;
  final void Function(int row)? onToggleDeleteRow;
  final void Function(int row)? onRevertRow;

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
          canFilter == other.canFilter &&
          hasStagingBuffer == other.hasStagingBuffer &&
          dataTypeName == other.dataTypeName &&
          onSecondaryTap == other.onSecondaryTap &&
          onCommitEdit == other.onCommitEdit &&
          onCancelEdit == other.onCancelEdit &&
          onOpenInspector == other.onOpenInspector &&
          onCopyCell == other.onCopyCell &&
          onFilterByValue == other.onFilterByValue &&
          onFilterComparison == other.onFilterComparison &&
          onSetNull == other.onSetNull &&
          onSetEmpty == other.onSetEmpty &&
          onRevertCell == other.onRevertCell &&
          onDuplicateRow == other.onDuplicateRow &&
          onToggleDeleteRow == other.onToggleDeleteRow &&
          onRevertRow == other.onRevertRow;

  List<MenuItem> _buildContextMenuItems(material.BuildContext context) {
    gridCellContextMenuItemsBuiltCount++;
    final preview = text.length > 24 ? '${text.substring(0, 22)}…' : text;
    final isNull = text == 'NULL';
    final numVal = num.tryParse(text);

    return [
      MenuButton(
        leading:
            const material.Icon(material.Icons.content_copy_rounded, size: 16),
        trailing: const material.Text('Ctrl+C',
            style: material.TextStyle(fontSize: 11)),
        onPressed: (_) => onCopyCell?.call(row, column),
        child: const material.Text('Copy Value'),
      ),
      MenuButton(
        leading:
            const material.Icon(material.Icons.table_chart_outlined, size: 16),
        trailing: const material.Text('Ctrl+Shift+C',
            style: material.TextStyle(fontSize: 11)),
        onPressed: (_) => onCopyCell?.call(row, column, withHeaders: true),
        child: const material.Text('Copy with Headers'),
      ),
      MenuButton(
        leading:
            const material.Icon(material.Icons.data_object_rounded, size: 16),
        onPressed: (_) => onCopyCell?.call(row, column, asJson: true),
        child: const material.Text('Copy as JSON'),
      ),
      MenuButton(
        leading: const material.Icon(material.Icons.grid_on_rounded, size: 16),
        onPressed: (_) => onCopyCell?.call(row, column, asCsv: true),
        child: const material.Text('Copy as CSV'),
      ),
      if (canFilter && columnName.isNotEmpty) ...[
        const MenuDivider(),
        MenuButton(
          leading:
              const material.Icon(material.Icons.filter_alt_outlined, size: 16),
          onPressed: (_) => onFilterByValue?.call(row, column, invert: false),
          child: material.Text(
            isNull
                ? 'Filter by NULL ($columnName IS NULL)'
                : 'Filter by Value ($columnName = $preview)',
          ),
        ),
        MenuButton(
          leading: const material.Icon(material.Icons.filter_alt_off_outlined,
              size: 16),
          onPressed: (_) => onFilterByValue?.call(row, column, invert: true),
          child: material.Text(
            isNull
                ? 'Filter Out NULL ($columnName IS NOT NULL)'
                : 'Filter Out ($columnName != $preview)',
          ),
        ),
        if (numVal != null) ...[
          MenuButton(
            leading: const material.Icon(material.Icons.chevron_right_rounded,
                size: 16),
            onPressed: (_) => onFilterComparison?.call(row, column, '>'),
            child: material.Text('Filter > $text ($columnName > $text)'),
          ),
          MenuButton(
            leading: const material.Icon(material.Icons.chevron_left_rounded,
                size: 16),
            onPressed: (_) => onFilterComparison?.call(row, column, '<'),
            child: material.Text('Filter < $text ($columnName < $text)'),
          ),
        ],
      ],
      const MenuDivider(),
      MenuButton(
        leading:
            const material.Icon(material.Icons.visibility_outlined, size: 16),
        trailing: const material.Text('Ctrl+I',
            style: material.TextStyle(fontSize: 11)),
        onPressed: (_) => onOpenInspector?.call(row, column),
        child: const material.Text('Inspect Cell Value…'),
      ),
      if (hasStagingBuffer) ...[
        MenuButton(
          leading: const material.Icon(
              material.Icons.remove_circle_outline_rounded,
              size: 16),
          trailing: const material.Text('Alt+N',
              style: material.TextStyle(fontSize: 11)),
          onPressed: (_) => onSetNull?.call(row, column),
          child: const material.Text('Set NULL'),
        ),
        MenuButton(
          leading: const material.Icon(material.Icons.format_clear_rounded,
              size: 16),
          onPressed: (_) => onSetEmpty?.call(row, column),
          child: const material.Text('Set to Empty String'),
        ),
        if (cellStatus == StagedCellStatus.modified)
          MenuButton(
            leading: const material.Icon(material.Icons.undo_rounded, size: 16),
            onPressed: (_) => onRevertCell?.call(row, column),
            child: const material.Text('Revert Cell Changes'),
          ),
        const MenuDivider(),
        MenuButton(
          leading: const material.Icon(material.Icons.content_paste_go_rounded,
              size: 16),
          trailing: const material.Text('Ctrl+D',
              style: material.TextStyle(fontSize: 11)),
          onPressed: (_) => onDuplicateRow?.call(row),
          child: const material.Text('Duplicate Row'),
        ),
        MenuButton(
          leading: material.Icon(
            rowStatus == StagedRowStatus.deleted
                ? material.Icons.restore_from_trash_rounded
                : material.Icons.delete_outline_rounded,
            size: 16,
            color: rowStatus == StagedRowStatus.deleted
                ? null
                : colorScheme.destructive,
          ),
          onPressed: (_) => onToggleDeleteRow?.call(row),
          child: material.Text(
            rowStatus == StagedRowStatus.deleted
                ? 'Restore Deleted Row'
                : 'Delete Row',
            style: material.TextStyle(
              color: rowStatus == StagedRowStatus.deleted
                  ? null
                  : colorScheme.destructive,
            ),
          ),
        ),
        if (rowStatus == StagedRowStatus.modified ||
            rowStatus == StagedRowStatus.deleted)
          MenuButton(
            leading:
                const material.Icon(material.Icons.restore_rounded, size: 16),
            onPressed: (_) => onRevertRow?.call(row),
            child: const material.Text('Revert Row Changes'),
          ),
      ],
    ];
  }

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

    var style = material.TextStyle(
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

    var bg = isSelected
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

    final cell = material.Container(
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

    // Tap / double-tap / drag-select are handled by one Listener at the grid
    // level (_onGridPointerDown/Move/Up + _cellAtOffset hit-testing) instead
    // of a GestureDetector per cell, and the cursor by one grid-level
    // MouseRegion instead of one per cell (#983) — both were previously
    // among the ~10 widgets/render objects built for every visible cell.
    material.Widget content = cell;
    final tooltip = ResultGridMetrics.cellTooltipMessage(
      text: text,
      dataTypeName: dataTypeName,
      columnName: columnName,
    );
    if (tooltip != null) {
      content = material.Tooltip(
        message: tooltip,
        waitDuration: kQueryaTooltipWait,
        child: content,
      );
    }

    // The row this cell belongs to carries one semantics node with a label
    // for all its visible cells (see _DataRow._semanticsLabel, #981); a
    // GestureDetector/Tooltip/Text node per cell on top of that would be
    // redundant and is one of the grid's largest per-frame costs.
    return material.ExcludeSemantics(
      child: material.Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            onSecondaryTap?.call(row, column);
          }
        },
        child: ContextMenu(
          // Lazy: right-clicking a cell is rare relative to how often cells
          // get rebuilt (scroll, selection, ...); building the item list
          // eagerly on every build was pure waste (#983).
          itemsBuilder: _buildContextMenuItems,
          child: content,
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
