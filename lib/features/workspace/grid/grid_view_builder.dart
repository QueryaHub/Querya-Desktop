// ignore_for_file: invalid_use_of_protected_member

part of '../result_grid_view.dart';

/// Widget tree for [VirtualResultGrid].
extension _GridViewBuilder on _VirtualResultGridState {
  material.Widget _buildGrid(material.BuildContext context) {
    if (_widthsNeedUpdate && !_userHasResized) {
      _columnWidths = _computeColumnWidths();
      _columnOffsets = computeResultGridColumnOffsets(_columnWidths);
      _widthsNeedUpdate = false;
    }
    final cs = Theme.of(context).colorScheme;

    return material.CallbackShortcuts(
      bindings: {
        const material.SingleActivator(
          LogicalKeyboardKey.keyC,
          meta: true,
        ): () => _copySelection(),
        const material.SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
        ): () => _copySelection(),
        const material.SingleActivator(
          LogicalKeyboardKey.keyC,
          meta: true,
          shift: true,
        ): () => _copySelection(withHeaders: true),
        const material.SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          shift: true,
        ): () => _copySelection(withHeaders: true),
        const material.SingleActivator(
          LogicalKeyboardKey.keyD,
          control: true,
        ): () {
          if (widget.stagingBuffer != null && _selection != null) {
            _handleDuplicateRow(_selection!.startRow);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.keyD,
          meta: true,
        ): () {
          if (widget.stagingBuffer != null && _selection != null) {
            _handleDuplicateRow(_selection!.startRow);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.insert,
          control: true,
        ): () => widget.stagingBuffer?.addRow(),
        const material.SingleActivator(
          LogicalKeyboardKey.keyN,
          meta: true,
        ): () {
          if (widget.stagingBuffer != null) {
            widget.stagingBuffer!.addRow();
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.delete,
          control: true,
        ): () {
          if (widget.stagingBuffer != null && _selection != null) {
            widget.stagingBuffer!
                .toggleDeleteRow(_toModelRowIndex(_selection!.startRow));
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.backspace,
          meta: true,
        ): () {
          if (widget.stagingBuffer != null && _selection != null) {
            widget.stagingBuffer!
                .toggleDeleteRow(_toModelRowIndex(_selection!.startRow));
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
        ): () {
          if (widget.stagingBuffer != null && _selection != null) {
            widget.stagingBuffer!
                .revertRow(_toModelRowIndex(_selection!.startRow));
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
        ): () {
          if (widget.stagingBuffer != null && _selection != null) {
            widget.stagingBuffer!
                .revertRow(_toModelRowIndex(_selection!.startRow));
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.escape,
        ): () {
          if (_editingCell != null) {
            _cancelEdit();
          } else {
            widget.onRowSelected?.call(null);
            setState(() {
              _selection = null;
              _selectionAnchor = null;
              _selectionFocus = null;
            });
            _notifySelectionAndFocus();
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.f2,
        ): () {
          if (_selection != null && _editingCell == null) {
            _startEditing(_selection!.startRow, _selection!.startColumn);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.enter,
        ): () {
          if (_selection != null && _editingCell == null) {
            _startEditing(_selection!.startRow, _selection!.startColumn);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.numpadEnter,
        ): () {
          if (_selection != null && _editingCell == null) {
            _startEditing(_selection!.startRow, _selection!.startColumn);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.space,
        ): () {
          if (_selection != null && _editingCell == null) {
            _openInspector(_selection!.startRow, _selection!.startColumn);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.keyI,
          control: true,
        ): () {
          if (_selection != null && _editingCell == null) {
            _openInspector(_selection!.startRow, _selection!.startColumn);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.keyI,
          meta: true,
        ): () {
          if (_selection != null && _editingCell == null) {
            _openInspector(_selection!.startRow, _selection!.startColumn);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.keyN,
          alt: true,
        ): () {
          if (_selection != null && widget.stagingBuffer != null) {
            _handleSetNull(_selection!.startRow, _selection!.startColumn);
          }
        },

        // Navigation: Arrows
        const material.SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _navigateCell(1, 0),
        const material.SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _navigateCell(-1, 0),
        const material.SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _navigateCell(0, 1),
        const material.SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _navigateCell(0, -1),

        // Navigation: Shift + Arrows (range selection)
        const material.SingleActivator(
          LogicalKeyboardKey.arrowDown,
          shift: true,
        ): () => _navigateCell(1, 0, extendSelection: true),
        const material.SingleActivator(
          LogicalKeyboardKey.arrowUp,
          shift: true,
        ): () => _navigateCell(-1, 0, extendSelection: true),
        const material.SingleActivator(
          LogicalKeyboardKey.arrowRight,
          shift: true,
        ): () => _navigateCell(0, 1, extendSelection: true),
        const material.SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          shift: true,
        ): () => _navigateCell(0, -1, extendSelection: true),

        // Navigation: Home / End (column jump)
        const material.SingleActivator(LogicalKeyboardKey.home): () =>
            _jumpToCell(column: 0),
        const material.SingleActivator(
          LogicalKeyboardKey.home,
          shift: true,
        ): () => _jumpToCell(column: 0, extendSelection: true),
        const material.SingleActivator(LogicalKeyboardKey.end): () =>
            _jumpToCell(column: widget.columns.length - 1),
        const material.SingleActivator(
          LogicalKeyboardKey.end,
          shift: true,
        ): () => _jumpToCell(
              column: widget.columns.length - 1,
              extendSelection: true,
            ),

        // Navigation: Ctrl+Home / Ctrl+End (table start / end)
        const material.SingleActivator(
          LogicalKeyboardKey.home,
          control: true,
        ): () => _jumpToCell(row: 0, column: 0),
        const material.SingleActivator(
          LogicalKeyboardKey.home,
          meta: true,
        ): () => _jumpToCell(row: 0, column: 0),
        const material.SingleActivator(
          LogicalKeyboardKey.home,
          control: true,
          shift: true,
        ): () => _jumpToCell(row: 0, column: 0, extendSelection: true),
        const material.SingleActivator(
          LogicalKeyboardKey.home,
          meta: true,
          shift: true,
        ): () => _jumpToCell(row: 0, column: 0, extendSelection: true),
        const material.SingleActivator(
          LogicalKeyboardKey.end,
          control: true,
        ): () => _jumpToCell(
              row: _sortedRows.length - 1,
              column: widget.columns.length - 1,
            ),
        const material.SingleActivator(
          LogicalKeyboardKey.end,
          meta: true,
        ): () => _jumpToCell(
              row: _sortedRows.length - 1,
              column: widget.columns.length - 1,
            ),
        const material.SingleActivator(
          LogicalKeyboardKey.end,
          control: true,
          shift: true,
        ): () => _jumpToCell(
              row: _sortedRows.length - 1,
              column: widget.columns.length - 1,
              extendSelection: true,
            ),
        const material.SingleActivator(
          LogicalKeyboardKey.end,
          meta: true,
          shift: true,
        ): () => _jumpToCell(
              row: _sortedRows.length - 1,
              column: widget.columns.length - 1,
              extendSelection: true,
            ),

        // Navigation: PageUp / PageDown
        const material.SingleActivator(LogicalKeyboardKey.pageDown): () =>
            _navigateCell(20, 0),
        const material.SingleActivator(
          LogicalKeyboardKey.pageDown,
          shift: true,
        ): () => _navigateCell(20, 0, extendSelection: true),
        const material.SingleActivator(LogicalKeyboardKey.pageUp): () =>
            _navigateCell(-20, 0),
        const material.SingleActivator(
          LogicalKeyboardKey.pageUp,
          shift: true,
        ): () => _navigateCell(-20, 0, extendSelection: true),

        // Select All: Ctrl+A / Meta+A
        const material.SingleActivator(
          LogicalKeyboardKey.keyA,
          control: true,
        ): () => _selectAll(),
        const material.SingleActivator(
          LogicalKeyboardKey.keyA,
          meta: true,
        ): () => _selectAll(),
      },
      child: material.Focus(
        focusNode: _focusNode,
        child: material.RepaintBoundary(
          child: material.LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final headerHeight = _scaledHeaderHeight(context);
              final rowHeight = _scaledRowHeight(context);
              final rowsViewportHeight =
                  math.max(0.0, constraints.maxHeight - headerHeight);
              _currentAvailableWidth = availableWidth;
              _currentRowsViewportHeight = rowsViewportHeight;

              var displayWidths = _columnWidths;
              var tableWidth = _tableWidth;
              if (!_userHasResized &&
                  tableWidth < availableWidth &&
                  _columnWidths.isNotEmpty) {
                if (identical(_distributedForColumnWidths, _columnWidths) &&
                    _distributedForAvailableWidth == availableWidth) {
                  displayWidths = _distributedWidths;
                } else {
                  displayWidths = distributeResultGridSpareWidth(
                    columnWidths: _columnWidths,
                    columns: widget.columns,
                    rows: _baseRows,
                    availableWidth: availableWidth,
                    maxColumnWidth:
                        context.scaled(ResultGridMetrics.maxColumnWidth),
                  );
                  _distributedWidths = displayWidths;
                  _distributedForColumnWidths = _columnWidths;
                  _distributedForAvailableWidth = availableWidth;
                  columnWidthDistributionCount++;
                }
                final distributedWidth =
                    displayWidths.fold<double>(0.0, (sum, w) => sum + w);
                tableWidth = math.max(distributedWidth, availableWidth);
              } else if (tableWidth < availableWidth) {
                tableWidth = availableWidth;
              }

              _currentDisplayOffsets = identical(displayWidths, _columnWidths)
                  ? _columnOffsets
                  : computeResultGridColumnOffsets(displayWidths);

              final window = _columnWindow(displayWidths, availableWidth);
              _currentDisplayWidths = displayWidths;
              _currentWindow = window;

              return material.Scrollbar(
                controller: _horizontalController,
                thumbVisibility: true,
                notificationPredicate: (_) => true,
                child: material.SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: material.Axis.horizontal,
                  child: material.SizedBox(
                    width: tableWidth,
                    child: material.Column(
                      crossAxisAlignment: material.CrossAxisAlignment.stretch,
                      children: [
                        _HeaderRow(
                          columns: widget.columns,
                          columnWidths: displayWidths,
                          window: window,
                          height: headerHeight,
                          colorScheme: cs,
                          sortColumnIndex: _sortColumnIndex,
                          sortOrder: _sortOrder,
                          onSortColumn: _toggleSort,
                          onResizeColumn: _onColumnResize,
                          onAutoFitColumn: _onColumnAutoFit,
                        ),
                        material.Expanded(
                          child: material.Scrollbar(
                            controller: _verticalController,
                            thumbVisibility: true,
                            // One grid-level cursor region instead of one
                            // MouseRegion per visible cell (#983). Matches
                            // the previous per-cell behavior exactly: cursor
                            // was already uniform across every cell based
                            // solely on whether a staging buffer exists, not
                            // on which specific cell is hovered.
                            child: material.MouseRegion(
                              cursor: widget.stagingBuffer != null
                                  ? material.SystemMouseCursors.text
                                  : material.SystemMouseCursors.basic,
                              child: material.Listener(
                                behavior: material.HitTestBehavior.translucent,
                                onPointerDown: (e) =>
                                    _onGridPointerDown(e, rowHeight: rowHeight),
                                onPointerMove: (e) =>
                                    _onGridPointerMove(e, rowHeight: rowHeight),
                                onPointerUp: (e) =>
                                    _onGridPointerUp(e, rowHeight: rowHeight),
                                onPointerCancel: _onGridPointerCancel,
                                child: material.ListView.builder(
                                  controller: _verticalController,
                                  itemCount: _sortedRows.length,
                                  itemExtent: rowHeight,
                                  itemBuilder: (context, rowIndex) {
                                    final row = _sortedRows[rowIndex];
                                    final isEven = rowIndex.isEven;
                                    final candidate = _DataRow(
                                      key: ValueKey('result-row-$rowIndex'),
                                      rowIndex: rowIndex,
                                      modelRowIndex: _toModelRowIndex(rowIndex),
                                      row: row,
                                      columns: widget.columns,
                                      columnWidths: displayWidths,
                                      window: window,
                                      height: rowHeight,
                                      colorScheme: cs,
                                      striped: !isEven,
                                      selection: _selectionForRow(rowIndex),
                                      stagingBuffer: widget.stagingBuffer,
                                      stagedSignature: widget.stagingBuffer
                                              ?.rowRenderSignature(
                                                  _toModelRowIndex(rowIndex)) ??
                                          0,
                                      editingCell: _editingCell?.row == rowIndex
                                          ? _editingCell
                                          : null,
                                      canFilter:
                                          widget.onFilterRequested != null,
                                      onCellSecondaryTap: _cellSecondaryTapCb,
                                      onCommitEdit: _commitEditCb,
                                      onCancelEdit: _cancelEditCb,
                                      onOpenInspector: _openInspectorCb,
                                      onCopyCell: _copyCellCb,
                                      onFilterByValue: _filterByValueCb,
                                      onFilterComparison: _filterComparisonCb,
                                      onSetNull: _setNullCb,
                                      onSetEmpty: _setEmptyCb,
                                      onRevertCell: _revertCellCb,
                                      onDuplicateRow: _duplicateRowCb,
                                      onToggleDeleteRow: _toggleDeleteRowCb,
                                      onRevertRow: _revertRowCb,
                                      columnDataTypes: widget.columnDataTypes,
                                    );
                                    final previous = _rowWidgets[rowIndex];
                                    if (previous != null &&
                                        previous.sameAs(candidate)) {
                                      return previous;
                                    }
                                    _rowWidgets[rowIndex] = candidate;
                                    if (_rowWidgets.length > 200) {
                                      _rowWidgets.removeWhere(
                                        (idx, _) =>
                                            (idx - rowIndex).abs() > 100,
                                      );
                                    }
                                    return candidate;
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
