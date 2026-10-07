// ignore_for_file: invalid_use_of_protected_member

part of '../result_grid_view.dart';

/// Pointer, drag and tap selection for [VirtualResultGrid].
extension _GridPointerSelection on _VirtualResultGridState {
  void _notifySelectionAndFocus() {
    if (widget.onSelectionValuesChanged != null) {
      if (_selection == null) {
        widget.onSelectionValuesChanged!(const []);
      } else {
        final rows = _sortedRows;
        final values = <String>[];
        for (var r = _selection!.startRow; r <= _selection!.endRow; r++) {
          if (r >= 0 && r < rows.length) {
            for (var c = _selection!.startColumn;
                c <= _selection!.endColumn;
                c++) {
              if (c >= 0 && c < rows[r].length) {
                values.add(rows[r][c]);
              }
            }
          }
        }
        widget.onSelectionValuesChanged!(values);
      }
    }

    if (widget.onCellFocused != null && _selectionAnchor != null) {
      final r = _selectionAnchor!.row;
      final c = _selectionAnchor!.column;
      final rows = _sortedRows;
      if (r >= 0 && r < rows.length && c >= 0 && c < widget.columns.length) {
        final colName = widget.columns[c];
        final val = c < rows[r].length ? rows[r][c] : '';
        final modelRow = _toModelRowIndex(r);
        widget.onCellFocused!(colName, val, modelRow);
      }
    }
  }

  ResultGridCellCoordinate? _cellAtOffset({
    required Offset localPosition,
    required double rowHeight,
  }) {
    if (_sortedRows.isEmpty || widget.columns.isEmpty) return null;
    final rowCount = _sortedRows.length;
    final colCount = widget.columns.length;

    final verticalOffset =
        _verticalController.hasClients ? _verticalController.offset : 0.0;
    final tableY = localPosition.dy + verticalOffset;
    final rowIndex = (tableY / rowHeight).floor().clamp(0, rowCount - 1);

    final tableX = localPosition.dx;
    final offsets = _currentDisplayOffsets.length >= colCount + 1
        ? _currentDisplayOffsets
        : _columnOffsets;
    int colIndex = colCount - 1;
    for (var i = 0; i < colCount; i++) {
      if (i + 1 < offsets.length && tableX < offsets[i + 1]) {
        colIndex = i;
        break;
      }
    }
    colIndex = colIndex.clamp(0, colCount - 1);

    return ResultGridCellCoordinate(rowIndex, colIndex);
  }

  void _onGridPointerDown(
    PointerDownEvent event, {
    required double rowHeight,
  }) {
    if (event.buttons != kPrimaryMouseButton) return;
    if (_sortedRows.isEmpty || widget.columns.isEmpty) return;

    if (_editingCell != null) {
      final downCell = _cellAtOffset(
        localPosition: event.localPosition,
        rowHeight: rowHeight,
      );
      if (downCell == _editingCell) {
        // The press landed on the cell currently being edited (e.g. to move
        // the caret or select text inside the open GridCellEditor) — let the
        // editor's own gesture handling deal with it instead of cancelling
        // the in-progress edit out from under the user (#1006).
        return;
      }
      _cancelEdit();
    }

    _isPointerDown = true;
    _isDragSelecting = false;
    _hasJustDragSelected = false;
    _pointerDownGlobalPos = event.position;
    _pointerDownLocalPos = event.localPosition;
    _lastPointerLocalPos = event.localPosition;
  }

  void _onGridPointerMove(
    PointerMoveEvent event, {
    required double rowHeight,
  }) {
    if (!_isPointerDown) return;
    _lastPointerLocalPos = event.localPosition;

    if (!_isDragSelecting) {
      final delta = (event.position - _pointerDownGlobalPos).distance;
      if (delta > 4.0) {
        _isDragSelecting = true;
        _hasJustDragSelected = false;
        final startCell = _cellAtOffset(
          localPosition: _pointerDownLocalPos,
          rowHeight: rowHeight,
        );
        if (startCell != null) {
          final isShift = HardwareKeyboard.instance.isShiftPressed;
          if (!isShift || _selectionAnchor == null) {
            _selectionAnchor = startCell;
          }
          _selectionFocus = startCell;
          _selection = ResultGridSelection.fromPoints(
            anchor: _selectionAnchor!,
            focus: startCell,
          );
          _focusNode.requestFocus();
          final modelRow = _toModelRowIndex(startCell.row);
          widget.onRowSelected?.call(modelRow);
          _notifySelectionAndFocus();
          setState(() {});
        }
        _startAutoScroll(rowHeight);
      }
    }

    if (_isDragSelecting) {
      final currentCell = _cellAtOffset(
        localPosition: event.localPosition,
        rowHeight: rowHeight,
      );
      if (currentCell != null && currentCell != _selectionFocus) {
        setState(() {
          _selectionFocus = currentCell;
          _selection = ResultGridSelection.fromPoints(
            anchor: _selectionAnchor ?? currentCell,
            focus: currentCell,
          );
        });
        final modelRow = _toModelRowIndex(currentCell.row);
        widget.onRowSelected?.call(modelRow);
        _notifySelectionAndFocus();
      }
    }
  }

  void _onGridPointerUp(
    PointerUpEvent event, {
    required double rowHeight,
  }) {
    if (_isDragSelecting) {
      _hasJustDragSelected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _hasJustDragSelected = false;
      });
    } else if (_isPointerDown) {
      // A plain click (never crossed the drag threshold): resolve which
      // cell was pressed — the down position is the more accurate "which
      // cell did the user click" signal than wherever the pointer lifted —
      // and treat it as a tap, or as a double-tap if it lands on the same
      // cell as the last qualifying tap within the platform's double-tap
      // window (#983: replaces a per-cell GestureDetector).
      final cell = _cellAtOffset(
        localPosition: _pointerDownLocalPos,
        rowHeight: rowHeight,
      );
      if (cell != null) {
        final now = DateTime.now();
        final isDoubleTap = _lastTapCell == cell &&
            _lastTapUpTime != null &&
            now.difference(_lastTapUpTime!) <= kDoubleTapTimeout;
        final isShift = HardwareKeyboard.instance.isShiftPressed;
        _onCellTap(cell.row, cell.column, isShift: isShift);
        if (isDoubleTap) {
          _startEditing(cell.row, cell.column);
          _lastTapUpTime = null;
          _lastTapCell = null;
        } else {
          _lastTapUpTime = now;
          _lastTapCell = cell;
        }
      }
    }
    _isPointerDown = false;
    _isDragSelecting = false;
    _stopAutoScroll();
  }

  void _onGridPointerCancel(PointerCancelEvent event) {
    _isPointerDown = false;
    _isDragSelecting = false;
    _stopAutoScroll();
  }

  void _startAutoScroll(double rowHeight) {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!_isDragSelecting || _lastPointerLocalPos == null || !mounted) {
        _stopAutoScroll();
        return;
      }
      _performAutoScrollAndSelection(rowHeight);
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _performAutoScrollAndSelection(double rowHeight) {
    if (!mounted) {
      _stopAutoScroll();
      return;
    }
    final pos = _lastPointerLocalPos;
    if (pos == null) return;

    const edgeMargin = 32.0;
    const maxVelocity = 15.0;

    double dyScroll = 0.0;
    if (pos.dy < edgeMargin) {
      final factor = ((edgeMargin - pos.dy) / edgeMargin).clamp(0.0, 3.0);
      dyScroll = -maxVelocity * factor;
    } else if (pos.dy > _currentRowsViewportHeight - edgeMargin) {
      final factor =
          ((pos.dy - (_currentRowsViewportHeight - edgeMargin)) / edgeMargin)
              .clamp(0.0, 3.0);
      dyScroll = maxVelocity * factor;
    }

    double dxScroll = 0.0;
    final hOffset =
        _horizontalController.hasClients ? _horizontalController.offset : 0.0;
    final screenX = pos.dx - hOffset;
    if (screenX < edgeMargin) {
      final factor = ((edgeMargin - screenX) / edgeMargin).clamp(0.0, 3.0);
      dxScroll = -maxVelocity * factor;
    } else if (screenX > _currentAvailableWidth - edgeMargin) {
      final factor =
          ((screenX - (_currentAvailableWidth - edgeMargin)) / edgeMargin)
              .clamp(0.0, 3.0);
      dxScroll = maxVelocity * factor;
    }

    if (dyScroll != 0.0 && _verticalController.hasClients) {
      final targetY = (_verticalController.offset + dyScroll).clamp(
        0.0,
        _verticalController.position.maxScrollExtent,
      );
      if (targetY != _verticalController.offset) {
        _verticalController.jumpTo(targetY);
      }
    }

    if (dxScroll != 0.0 && _horizontalController.hasClients) {
      final targetX = (_horizontalController.offset + dxScroll).clamp(
        0.0,
        _horizontalController.position.maxScrollExtent,
      );
      if (targetX != _horizontalController.offset) {
        _horizontalController.jumpTo(targetX);
      }
    }

    final currentCell = _cellAtOffset(
      localPosition: pos,
      rowHeight: rowHeight,
    );
    if (currentCell != null && currentCell != _selectionFocus) {
      setState(() {
        _selectionFocus = currentCell;
        _selection = ResultGridSelection.fromPoints(
          anchor: _selectionAnchor ?? currentCell,
          focus: currentCell,
        );
      });
      final modelRow = _toModelRowIndex(currentCell.row);
      widget.onRowSelected?.call(modelRow);
      _notifySelectionAndFocus();
    }
  }

  void _onCellTap(int row, int column, {bool isShift = false}) {
    if (_isDragSelecting || _hasJustDragSelected) {
      _hasJustDragSelected = false;
      return;
    }
    _focusNode.requestFocus();
    final modelRow = _toModelRowIndex(row);
    widget.onRowSelected?.call(modelRow);
    setState(() {
      final coord = ResultGridCellCoordinate(row, column);
      if (isShift && _selectionAnchor != null) {
        _selectionFocus = coord;
        _selection = ResultGridSelection.fromPoints(
          anchor: _selectionAnchor!,
          focus: coord,
        );
      } else {
        _selectionAnchor = coord;
        _selectionFocus = coord;
        _selection = ResultGridSelection(
          startRow: row,
          startColumn: column,
          endRow: row,
          endColumn: column,
        );
      }
    });
    _notifySelectionAndFocus();
  }

  void _onCellSecondaryTap(int row, int column) {
    _focusNode.requestFocus();
    widget.onRowSelected?.call(row);
    if (_selection != null && _selection!.contains(row, column)) {
      // Keep existing selection intact so context menu operates on whole selection if clicked inside
    } else {
      setState(() {
        final coord = ResultGridCellCoordinate(row, column);
        _selectionAnchor = coord;
        _selectionFocus = coord;
        _selection = ResultGridSelection(
          startRow: row,
          startColumn: column,
          endRow: row,
          endColumn: column,
        );
      });
      _notifySelectionAndFocus();
    }
  }

}
