// ignore_for_file: invalid_use_of_protected_member

part of '../result_grid_view.dart';

/// Scroll, column sizing and sorting for [VirtualResultGrid].
extension _GridViewLayout on _VirtualResultGridState {
  /// The scroll view already translates header and body together; the offset
  /// only decides which columns are built (virtualized window). So rebuild only
  /// when the viewport runs past the built window, not on every pan frame.
  void _onHorizontalScroll() {
    if (!_horizontalController.hasClients) return;
    final offset = _horizontalController.offset;
    if ((offset - _scrollOffset).abs() < 0.5) return;
    _scrollOffset = offset;

    final current = _currentWindow;
    if (current != null && _currentDisplayWidths.isNotEmpty) {
      final visible = computeVisibleColumnWindow(
        columnWidths: _currentDisplayWidths,
        columnOffsets: _currentDisplayOffsets,
        scrollOffset: offset,
        viewportWidth: _currentAvailableWidth,
        overscanColumns: 0,
      );
      // Every visible column is already built (the rest is overscan): keep the
      // window until the viewport reaches its edge, then recentre it.
      if (!visible.isEmpty &&
          current.first <= visible.first &&
          visible.last <= current.last) {
        return;
      }
    }
    setState(() {});
  }

  void _onColumnResize(int index, double delta) {
    if (index < 0 || index >= _columnWidths.length) return;
    setState(() {
      _userHasResized = true;
      final minWidth = context.scaled(ResultGridMetrics.minColumnWidth);
      final maxWidth = context.scaled(ResultGridMetrics.maxColumnWidth * 3);
      final newWidth = (_columnWidths[index] + delta).clamp(minWidth, maxWidth);
      _columnWidths = List<double>.from(_columnWidths);
      _columnWidths[index] = newWidth;
      _columnOffsets = computeResultGridColumnOffsets(_columnWidths);
      _widthsNeedUpdate = false;
    });
  }

  void _onColumnAutoFit(int index) {
    if (index < 0 ||
        index >= widget.columns.length ||
        index >= _columnWidths.length) {
      return;
    }
    final rows = _baseRows;
    final headerWidth = widget.columns[index].length * 7.5 + 38.0;
    var maxRowChars = 0;
    final sampleCount = math.min(rows.length, 200);
    for (var r = 0; r < sampleCount; r++) {
      if (index < rows[r].length && rows[r][index].length > maxRowChars) {
        maxRowChars = rows[r][index].length;
      }
    }
    final contentWidth = maxRowChars * 7.5 + 24.0;
    final naturalWidth = math.max(headerWidth, contentWidth);
    final minWidth = context.scaled(ResultGridMetrics.minColumnWidth);
    final maxWidth = context.scaled(ResultGridMetrics.maxColumnWidth * 3);
    final autoFitWidth = naturalWidth.clamp(minWidth, maxWidth);

    setState(() {
      _userHasResized = true;
      _columnWidths = List<double>.from(_columnWidths);
      _columnWidths[index] = autoFitWidth;
      _columnOffsets = computeResultGridColumnOffsets(_columnWidths);
      _widthsNeedUpdate = false;
    });
  }

  void _toggleSort(int columnIndex) {
    if (columnIndex < 0 || columnIndex >= widget.columns.length) return;
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        if (_sortOrder == ResultGridSortOrder.ascending) {
          _sortOrder = ResultGridSortOrder.descending;
        } else {
          _sortColumnIndex = null;
          _sortOrder = null;
        }
      } else {
        _sortColumnIndex = columnIndex;
        _sortOrder = ResultGridSortOrder.ascending;
      }
      _updateSortedRows();
    });
  }

  List<List<String>> get _baseRows {
    if (widget.rowIndicesMapping != null) {
      return widget.rows;
    }
    return widget.stagingBuffer?.effectiveRows ?? widget.rows;
  }

  void _updateSortedRows({bool asyncIfLarge = true}) {
    _rowWidgets.clear();
    final rows = _baseRows;
    if (_sortColumnIndex == null || _sortOrder == null) {
      _sortedRows = rows;
      if (widget.rowIndicesMapping != null) {
        _sortedToModelIndices = List<int>.from(widget.rowIndicesMapping!);
      } else {
        _sortedToModelIndices =
            List<int>.generate(rows.length, (i) => i, growable: false);
      }
      return;
    }

    final sortCol = _sortColumnIndex!;
    final sortOrd = _sortOrder!;
    final version = ++_sortVersion;

    if (asyncIfLarge && rows.length >= kSortIsolateThreshold) {
      foundation
          .compute(
        sortResultGridRowsWithIndicesIsolate,
        SortIsolateParams(rows: rows, columnIndex: sortCol, order: sortOrd),
      )
          .then((sortedData) {
        if (!mounted || version != _sortVersion) return;
        setState(() {
          _applySortedData(sortedData, rows);
        });
      }).catchError((_) {
        if (!mounted || version != _sortVersion) return;
        setState(() {
          final fallback = sortResultGridRowsWithIndices(
            rows: rows,
            columnIndex: sortCol,
            order: sortOrd,
          );
          _applySortedData(fallback, rows);
        });
      });
    } else {
      final sortedData = sortResultGridRowsWithIndices(
        rows: rows,
        columnIndex: sortCol,
        order: sortOrd,
      );
      _applySortedData(sortedData, rows);
    }
  }

  void _applySortedData(
      SortedResultGridData sortedData, List<List<String>> rows) {
    _rowWidgets.clear();
    _sortedRows = sortedData.rows;
    if (widget.rowIndicesMapping != null) {
      final mapping = widget.rowIndicesMapping!;
      _sortedToModelIndices = sortedData.sortedToModelIndices
          .map((i) => i < mapping.length ? mapping[i] : i)
          .toList(growable: false);
    } else {
      _sortedToModelIndices = sortedData.sortedToModelIndices;
    }
  }


  List<double> _computeColumnWidths() {
    return computeResultGridColumnWidths(
      columns: widget.columns,
      rows: _baseRows,
      minWidth: context.scaled(ResultGridMetrics.minColumnWidth),
      maxWidth: context.scaled(ResultGridMetrics.maxColumnWidth),
    );
  }

  double get _tableWidth {
    if (_columnWidths.isEmpty) return 0;
    return _columnOffsets[_columnWidths.length];
  }

  double _scaledRowHeight(material.BuildContext context) =>
      context.scaled(ResultGridMetrics.rowHeight);

  double _scaledHeaderHeight(material.BuildContext context) =>
      context.scaled(ResultGridMetrics.headerHeight);

  ResultGridColumnWindow _columnWindow(
    List<double> displayWidths,
    double viewportWidth,
  ) {
    final offsets = identical(displayWidths, _columnWidths)
        ? _columnOffsets
        : computeResultGridColumnOffsets(displayWidths);
    return computeVisibleColumnWindow(
      columnWidths: displayWidths,
      columnOffsets: offsets,
      scrollOffset: _scrollOffset,
      viewportWidth: viewportWidth,
    );
  }

}
