// ignore_for_file: invalid_use_of_protected_member

part of '../result_grid_view.dart';

/// Keyboard navigation and scroll-to-cell for [VirtualResultGrid].
extension _GridKeyboardNavigation on _VirtualResultGridState {
  void _scrollToCell(int row, int col) {
    if (!mounted) return;
    final rowHeight = _scaledRowHeight(context);
    final headerHeight = _scaledHeaderHeight(context);

    // Vertical scroll
    if (_verticalController.hasClients) {
      final targetTop = row * rowHeight;
      final targetBottom = targetTop + rowHeight;
      final currentOffset = _verticalController.offset;
      final viewportHeight =
          _verticalController.position.viewportDimension - headerHeight;

      if (targetTop < currentOffset) {
        _verticalController.jumpTo(targetTop.clamp(
          0.0,
          _verticalController.position.maxScrollExtent,
        ));
      } else if (targetBottom > currentOffset + viewportHeight &&
          viewportHeight > 0) {
        final newOffset = (targetBottom - viewportHeight).clamp(
          0.0,
          _verticalController.position.maxScrollExtent,
        );
        _verticalController.jumpTo(newOffset);
      }
    }

    // Horizontal scroll
    if (_horizontalController.hasClients &&
        col >= 0 &&
        col < _columnWidths.length) {
      final colLeft = _columnOffsets[col];
      final colRight = colLeft + _columnWidths[col];
      final currentOffset = _horizontalController.offset;
      final viewportWidth = _horizontalController.position.viewportDimension;

      if (colLeft < currentOffset) {
        _horizontalController.jumpTo(colLeft.clamp(
          0.0,
          _horizontalController.position.maxScrollExtent,
        ));
      } else if (colRight > currentOffset + viewportWidth &&
          viewportWidth > 0) {
        final newOffset = (colRight - viewportWidth).clamp(
          0.0,
          _horizontalController.position.maxScrollExtent,
        );
        _horizontalController.jumpTo(newOffset);
      }
    }
  }

  void _navigateCell(int dRow, int dCol, {bool extendSelection = false}) {
    if (_sortedRows.isEmpty || widget.columns.isEmpty) return;
    if (_editingCell != null) return;

    if (_selectionAnchor == null) {
      setState(() {
        _selectionAnchor = const ResultGridCellCoordinate(0, 0);
        _selectionFocus = const ResultGridCellCoordinate(0, 0);
        _selection = const ResultGridSelection(
          startRow: 0,
          startColumn: 0,
          endRow: 0,
          endColumn: 0,
        );
      });
      widget.onRowSelected?.call(0);
      _scrollToCell(0, 0);
      _notifySelectionAndFocus();
      return;
    }

    final currentFocus = _selectionFocus ?? _selectionAnchor!;
    final newRow = (currentFocus.row + dRow).clamp(0, _sortedRows.length - 1);
    final newCol =
        (currentFocus.column + dCol).clamp(0, widget.columns.length - 1);
    final newFocus = ResultGridCellCoordinate(newRow, newCol);

    setState(() {
      if (extendSelection) {
        _selectionFocus = newFocus;
        _selection = ResultGridSelection.fromPoints(
          anchor: _selectionAnchor!,
          focus: newFocus,
        );
      } else {
        _selectionAnchor = newFocus;
        _selectionFocus = newFocus;
        _selection = ResultGridSelection(
          startRow: newRow,
          startColumn: newCol,
          endRow: newRow,
          endColumn: newCol,
        );
        widget.onRowSelected?.call(newRow);
      }
    });

    _scrollToCell(newRow, newCol);
    _notifySelectionAndFocus();
  }

  void _jumpToCell({int? row, int? column, bool extendSelection = false}) {
    if (_sortedRows.isEmpty || widget.columns.isEmpty) return;
    if (_editingCell != null) return;

    final currentFocus = _selectionFocus ??
        _selectionAnchor ??
        const ResultGridCellCoordinate(0, 0);
    final newRow = (row ?? currentFocus.row).clamp(0, _sortedRows.length - 1);
    final newCol =
        (column ?? currentFocus.column).clamp(0, widget.columns.length - 1);
    final newFocus = ResultGridCellCoordinate(newRow, newCol);

    setState(() {
      if (extendSelection) {
        _selectionAnchor ??= currentFocus;
        _selectionFocus = newFocus;
        _selection = ResultGridSelection.fromPoints(
          anchor: _selectionAnchor!,
          focus: newFocus,
        );
      } else {
        _selectionAnchor = newFocus;
        _selectionFocus = newFocus;
        _selection = ResultGridSelection(
          startRow: newRow,
          startColumn: newCol,
          endRow: newRow,
          endColumn: newCol,
        );
        widget.onRowSelected?.call(newRow);
      }
    });

    _scrollToCell(newRow, newCol);
    _notifySelectionAndFocus();
  }

  void _selectAll() {
    if (_sortedRows.isEmpty || widget.columns.isEmpty) return;
    if (_editingCell != null) return;

    setState(() {
      _selectionAnchor = const ResultGridCellCoordinate(0, 0);
      _selectionFocus = ResultGridCellCoordinate(
        _sortedRows.length - 1,
        widget.columns.length - 1,
      );
      _selection = ResultGridSelection(
        startRow: 0,
        startColumn: 0,
        endRow: _sortedRows.length - 1,
        endColumn: widget.columns.length - 1,
      );
    });

    _notifySelectionAndFocus();
  }
}
