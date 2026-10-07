// ignore_for_file: invalid_use_of_protected_member

part of '../result_grid_view.dart';

/// Inline editing and inspector handling for [VirtualResultGrid].
extension _GridCellEditing on _VirtualResultGridState {
  void _startEditing(int row, int column) {
    if (widget.stagingBuffer == null) return;
    if (row < 0 ||
        row >= _sortedRows.length ||
        column < 0 ||
        column >= widget.columns.length) {
      return;
    }
    setState(() {
      _editingCell = ResultGridCellCoordinate(row, column);
      _selectionAnchor = _editingCell;
      _selectionFocus = _editingCell;
      _selection = ResultGridSelection(
        startRow: row,
        startColumn: column,
        endRow: row,
        endColumn: column,
      );
    });
  }

  /// The selection only when it touches [rowIndex]. Rows outside the range do
  /// not depend on it, so a selection change does not rebuild them.
  ResultGridSelection? _selectionForRow(int rowIndex) {
    final sel = _selection;
    if (sel == null || rowIndex < sel.startRow || rowIndex > sel.endRow) {
      return null;
    }
    return sel;
  }

  int _toModelRowIndex(int visualRow) {
    if (visualRow >= 0 && visualRow < _sortedToModelIndices.length) {
      return _sortedToModelIndices[visualRow];
    }
    return visualRow;
  }

  void _commitEdit(
    int row,
    int column,
    String value, {
    bool moveNextCol = false,
    bool movePrevCol = false,
    bool moveNextRow = false,
    bool movePrevRow = false,
  }) {
    if (widget.stagingBuffer != null) {
      final modelRow = _toModelRowIndex(row);
      widget.stagingBuffer!.setCell(modelRow, column, value);
    }
    setState(() {
      if (moveNextCol) {
        if (column + 1 < widget.columns.length) {
          _editingCell = ResultGridCellCoordinate(row, column + 1);
          _selection = ResultGridSelection(
            startRow: row,
            startColumn: column + 1,
            endRow: row,
            endColumn: column + 1,
          );
        } else if (row + 1 < _sortedRows.length) {
          _editingCell = ResultGridCellCoordinate(row + 1, 0);
          _selection = ResultGridSelection(
            startRow: row + 1,
            startColumn: 0,
            endRow: row + 1,
            endColumn: 0,
          );
        } else {
          _editingCell = null;
        }
      } else if (movePrevCol) {
        if (column > 0) {
          _editingCell = ResultGridCellCoordinate(row, column - 1);
          _selection = ResultGridSelection(
            startRow: row,
            startColumn: column - 1,
            endRow: row,
            endColumn: column - 1,
          );
        } else if (row > 0) {
          _editingCell =
              ResultGridCellCoordinate(row - 1, widget.columns.length - 1);
          _selection = ResultGridSelection(
            startRow: row - 1,
            startColumn: widget.columns.length - 1,
            endRow: row - 1,
            endColumn: widget.columns.length - 1,
          );
        } else {
          _editingCell = null;
        }
      } else if (moveNextRow) {
        if (row + 1 < _sortedRows.length) {
          _editingCell = ResultGridCellCoordinate(row + 1, column);
          _selection = ResultGridSelection(
            startRow: row + 1,
            startColumn: column,
            endRow: row + 1,
            endColumn: column,
          );
        } else {
          _editingCell = null;
        }
      } else if (movePrevRow) {
        if (row > 0) {
          _editingCell = ResultGridCellCoordinate(row - 1, column);
          _selection = ResultGridSelection(
            startRow: row - 1,
            startColumn: column,
            endRow: row - 1,
            endColumn: column,
          );
        } else {
          _editingCell = null;
        }
      } else {
        _editingCell = null;
      }
      if (_editingCell != null) {
        _selectionAnchor = _editingCell;
        _selectionFocus = _editingCell;
        widget.onRowSelected?.call(_editingCell!.row);
        _scrollToCell(_editingCell!.row, _editingCell!.column);
      }
    });
    _notifySelectionAndFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingCell = null;
    });
  }

  Future<void> _openInspector(int row, int column) async {
    if (row < 0 ||
        row >= _sortedRows.length ||
        column < 0 ||
        column >= widget.columns.length) {
      return;
    }
    final colName = widget.columns[column];
    final currentVal =
        column < _sortedRows[row].length ? _sortedRows[row][column] : '';
    final result = await showGridCellInspectorDialog(
      context: context,
      columnName: colName,
      initialValue: currentVal,
      rowIndex: row,
      dataTypeName: widget.columnDataTypes?[colName],
    );
    if (result != null && widget.stagingBuffer != null) {
      widget.stagingBuffer!.setCell(_toModelRowIndex(row), column, result);
    }
  }

}
