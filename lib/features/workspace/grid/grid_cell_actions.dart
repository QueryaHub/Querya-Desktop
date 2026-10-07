// ignore_for_file: invalid_use_of_protected_member

part of '../result_grid_view.dart';

/// Context-menu cell and row actions for [VirtualResultGrid].
extension _GridCellActions on _VirtualResultGridState {
  void _handleFilterByValue(int row, int col, {required bool invert}) {
    if (widget.onFilterRequested == null) return;
    if (_isPiiMasked(col)) return;
    if (col >= widget.columns.length || row >= _sortedRows.length) return;
    final colName = widget.columns[col];
    final rowData = _sortedRows[row];
    final cellVal = col < rowData.length ? rowData[col] : '';

    String expr;
    if (cellVal == 'NULL') {
      expr = invert ? '$colName IS NOT NULL' : '$colName IS NULL';
    } else if (num.tryParse(cellVal) != null) {
      expr = invert ? '$colName != $cellVal' : '$colName = $cellVal';
    } else {
      final escaped = cellVal.replaceAll("'", "''");
      expr = invert ? "$colName != '$escaped'" : "$colName = '$escaped'";
    }
    widget.onFilterRequested!(expr);
  }

  void _handleFilterComparison(int row, int col, String operator) {
    if (widget.onFilterRequested == null) return;
    if (_isPiiMasked(col)) return;
    if (col >= widget.columns.length || row >= _sortedRows.length) return;
    final colName = widget.columns[col];
    final rowData = _sortedRows[row];
    final cellVal = col < rowData.length ? rowData[col] : '';
    if (num.tryParse(cellVal) == null) return;

    widget.onFilterRequested!('$colName $operator $cellVal');
  }

  void _handleSetNull(int row, int col) {
    if (widget.stagingBuffer == null) return;
    final sel = (_selection != null && _selection!.contains(row, col))
        ? _selection!
        : ResultGridSelection(
            startRow: row, startColumn: col, endRow: row, endColumn: col);
    for (var r = sel.startRow; r <= sel.endRow; r++) {
      final modelRow = _toModelRowIndex(r);
      for (var c = sel.startColumn; c <= sel.endColumn; c++) {
        widget.stagingBuffer!.setCellNull(modelRow, c);
      }
    }
  }

  void _handleSetEmpty(int row, int col) {
    if (widget.stagingBuffer == null) return;
    final sel = (_selection != null && _selection!.contains(row, col))
        ? _selection!
        : ResultGridSelection(
            startRow: row, startColumn: col, endRow: row, endColumn: col);
    for (var r = sel.startRow; r <= sel.endRow; r++) {
      final modelRow = _toModelRowIndex(r);
      for (var c = sel.startColumn; c <= sel.endColumn; c++) {
        widget.stagingBuffer!.setCell(modelRow, c, '');
      }
    }
  }

  void _handleRevertCell(int row, int col) {
    if (widget.stagingBuffer == null) return;
    final sel = (_selection != null && _selection!.contains(row, col))
        ? _selection!
        : ResultGridSelection(
            startRow: row, startColumn: col, endRow: row, endColumn: col);
    for (var r = sel.startRow; r <= sel.endRow; r++) {
      final modelRow = _toModelRowIndex(r);
      for (var c = sel.startColumn; c <= sel.endColumn; c++) {
        widget.stagingBuffer!.revertCell(modelRow, c);
      }
    }
  }

  void _handleDuplicateRow(int row) {
    if (widget.stagingBuffer == null || row >= _sortedRows.length) return;
    widget.stagingBuffer!.duplicateRow(_toModelRowIndex(row));
  }

  void _handleToggleDeleteRow(int row) {
    if (widget.stagingBuffer == null || row >= _sortedRows.length) return;
    widget.stagingBuffer!.toggleDeleteRow(_toModelRowIndex(row));
  }

  void _handleRevertRow(int row) {
    if (widget.stagingBuffer == null || row >= _sortedRows.length) return;
    widget.stagingBuffer!.revertRow(_toModelRowIndex(row));
  }

}
