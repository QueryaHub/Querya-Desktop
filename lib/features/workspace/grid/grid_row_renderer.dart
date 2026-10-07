part of '../result_grid_view.dart';

class _DataRow extends material.StatefulWidget {
  const _DataRow({
    super.key,
    required this.rowIndex,
    required this.modelRowIndex,
    required this.row,
    required this.columns,
    required this.columnWidths,
    required this.window,
    required this.height,
    required this.colorScheme,
    required this.striped,
    this.selection,
    this.stagingBuffer,
    this.stagedSignature = 0,
    this.editingCell,
    this.canFilter = false,
    this.onCellSecondaryTap,
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
    this.columnDataTypes,
    this.piiKinds,
  });

  final int rowIndex;
  final int modelRowIndex;
  final List<String> row;
  final List<String> columns;
  final List<double> columnWidths;
  final ResultGridColumnWindow window;
  final double height;
  final ColorScheme colorScheme;
  final bool striped;
  final ResultGridSelection? selection;
  final DataGridStagingBuffer? stagingBuffer;

  /// [DataGridStagingBuffer.rowRenderSignature] of this row, so equality can
  /// see staged-state changes the (shared, mutable) buffer reference hides.
  final int stagedSignature;
  final ResultGridCellCoordinate? editingCell;
  final bool canFilter;
  final void Function(int row, int col)? onCellSecondaryTap;
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
  final Map<String, String>? columnDataTypes;

  /// Per-column PII kind while "Mask sensitive data" is on (null when off).
  final List<PiiKind?>? piiKinds;

  /// True when [other] would draw exactly the same row. The grid hands the
  /// framework the *previous* widget instance in that case, so
  /// [Element.updateChild] skips it and an edit, a selection change or a scroll
  /// only rebuilds the rows whose inputs actually changed.
  bool sameAs(_DataRow other) =>
      identical(this, other) ||
      rowIndex == other.rowIndex &&
          modelRowIndex == other.modelRowIndex &&
          identical(row, other.row) &&
          identical(columns, other.columns) &&
          (identical(columnWidths, other.columnWidths) ||
              foundation.listEquals(columnWidths, other.columnWidths)) &&
          window == other.window &&
          height == other.height &&
          colorScheme == other.colorScheme &&
          striped == other.striped &&
          selection == other.selection &&
          identical(stagingBuffer, other.stagingBuffer) &&
          stagedSignature == other.stagedSignature &&
          editingCell == other.editingCell &&
          canFilter == other.canFilter &&
          onCellSecondaryTap == other.onCellSecondaryTap &&
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
          onRevertRow == other.onRevertRow &&
          identical(columnDataTypes, other.columnDataTypes) &&
          identical(piiKinds, other.piiKinds);

  @override
  material.State<_DataRow> createState() => _DataRowState();

  /// One label for the whole row (visible columns only), read by screen
  /// readers instead of a separate semantics node per cell — see #981.
  String _semanticsLabel(StagedRowStatus rowStatus) {
    final buffer = StringBuffer('Row ${modelRowIndex + 1}');
    switch (rowStatus) {
      case StagedRowStatus.deleted:
        buffer.write(' (deleted)');
      case StagedRowStatus.inserted:
        buffer.write(' (new)');
      case StagedRowStatus.modified:
        buffer.write(' (modified)');
      case StagedRowStatus.unchanged:
        break;
    }
    for (var c = window.first; c <= window.last && c < columns.length; c++) {
      buffer.write(', ${columns[c]}: ${c < row.length ? row[c] : ''}');
    }
    return buffer.toString();
  }

  material.Widget _buildRow(Map<int, _GridCell> cache) {
    final rowStatus =
        stagingBuffer?.getRowStatus(modelRowIndex) ?? StagedRowStatus.unchanged;

    return material.Semantics(
      container: true,
      label: _semanticsLabel(rowStatus),
      child: material.RepaintBoundary(
        child: material.SizedBox(
          height: height,
          child: material.Row(
            children: [
              if (window.leadingWidth > 0)
                material.SizedBox(
                  key: const material.ValueKey('lead'),
                  width: window.leadingWidth,
                ),
              for (var c = window.first; c <= window.last; c++)
                _reuseCell(
                  cache,
                  c,
                  _GridCell(
                    key: material.ValueKey<int>(c),
                    row: rowIndex,
                    column: c,
                    columnName: c < columns.length ? columns[c] : '',
                    text: c < row.length
                        ? _maskCellText(piiKinds, c, row[c])
                        : '',
                    width: columnWidths[c],
                    colorScheme: colorScheme,
                    striped: striped,
                    rowStatus: rowStatus,
                    cellStatus:
                        stagingBuffer?.getCellStatus(modelRowIndex, c) ??
                            StagedCellStatus.clean,
                    isSelected: selection?.contains(rowIndex, c) ?? false,
                    isEditing: editingCell?.row == rowIndex &&
                        editingCell?.column == c,
                    isSelectionTop: selection != null &&
                        selection!.contains(rowIndex, c) &&
                        rowIndex == selection!.startRow,
                    isSelectionBottom: selection != null &&
                        selection!.contains(rowIndex, c) &&
                        rowIndex == selection!.endRow,
                    isSelectionLeft: selection != null &&
                        selection!.contains(rowIndex, c) &&
                        c == selection!.startColumn,
                    isSelectionRight: selection != null &&
                        selection!.contains(rowIndex, c) &&
                        c == selection!.endColumn,
                    canFilter: canFilter,
                    hasStagingBuffer: stagingBuffer != null,
                    dataTypeName:
                        columnDataTypes?[c < columns.length ? columns[c] : ''],
                    onSecondaryTap: onCellSecondaryTap,
                    onCommitEdit: onCommitEdit,
                    onCancelEdit: onCancelEdit,
                    onOpenInspector: onOpenInspector,
                    onCopyCell: onCopyCell,
                    onFilterByValue: onFilterByValue,
                    onFilterComparison: onFilterComparison,
                    onSetNull: onSetNull,
                    onSetEmpty: onSetEmpty,
                    onRevertCell: onRevertCell,
                    onDuplicateRow: onDuplicateRow,
                    onToggleDeleteRow: onToggleDeleteRow,
                    onRevertRow: onRevertRow,
                  ),
                ),
              if (window.trailingWidth > 0)
                material.SizedBox(
                  key: const material.ValueKey('trail'),
                  width: window.trailingWidth,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Returns the cell built last time for [column] when it would look the same,
/// so the framework skips it; otherwise remembers and returns [candidate].
_GridCell _reuseCell(
    Map<int, _GridCell> cache, int column, _GridCell candidate) {
  final previous = cache[column];
  if (previous != null && previous.sameAs(candidate)) return previous;
  cache[column] = candidate;
  return candidate;
}

class _DataRowState extends material.State<_DataRow> {
  final Map<int, _GridCell> _cells = {};

  @override
  material.Widget build(material.BuildContext context) {
    final w = widget.window;
    // Cells that scrolled out of the window are dropped, not kept alive.
    _cells.removeWhere((c, _) => c < w.first || c > w.last);
    return widget._buildRow(_cells);
  }
}

/// [value] hidden according to [kinds] (the per-column PII guesses).
String _maskCellText(List<PiiKind?>? kinds, int column, String value) {
  if (kinds == null || column >= kinds.length) return value;
  final kind = kinds[column];
  return kind == null ? value : maskPiiValue(kind, value);
}
