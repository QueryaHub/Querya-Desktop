import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HardwareKeyboard, LogicalKeyboardKey;
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/ui/querya_tooltip.dart';
import 'package:querya_desktop/features/main_screen/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/main_screen/grid_cell_editor.dart';
import 'package:querya_desktop/features/main_screen/grid_cell_popover_inspector.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Layout metrics for [VirtualResultGrid].
abstract final class ResultGridMetrics {
  static const double rowHeight = 36;
  static const double headerHeight = 36;
  static const double minColumnWidth = 120;
  static const double maxColumnWidth = 280;
  static const int columnWidthSampleRows = 40;
  static const int tooltipMinLength = 48;

  /// Extra columns built beyond the viewport to reduce scroll flicker.
  static const int columnOverscan = 2;
}

/// Inclusive visible column window with spacer widths for off-screen columns.
@immutable
class ResultGridColumnWindow {
  const ResultGridColumnWindow({
    required this.first,
    required this.last,
    required this.leadingWidth,
    required this.trailingWidth,
  });

  /// Empty window (no columns).
  static const empty = ResultGridColumnWindow(
    first: 0,
    last: -1,
    leadingWidth: 0,
    trailingWidth: 0,
  );

  /// Inclusive first visible (or overscanned) column index.
  final int first;

  /// Inclusive last visible (or overscanned) column index.
  final int last;

  /// Width of columns strictly before [first] (left spacer).
  final double leadingWidth;

  /// Width of columns strictly after [last] (right spacer).
  final double trailingWidth;

  bool get isEmpty => last < first;

  int get columnCount => isEmpty ? 0 : last - first + 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultGridColumnWindow &&
          first == other.first &&
          last == other.last &&
          leadingWidth == other.leadingWidth &&
          trailingWidth == other.trailingWidth;

  @override
  int get hashCode => Object.hash(first, last, leadingWidth, trailingWidth);
}

/// Computes fixed column widths from headers and a sample of [rows].
List<double> computeResultGridColumnWidths({
  required List<String> columns,
  required List<List<String>> rows,
  double minWidth = ResultGridMetrics.minColumnWidth,
  double maxWidth = ResultGridMetrics.maxColumnWidth,
  int sampleRowCount = ResultGridMetrics.columnWidthSampleRows,
}) {
  if (columns.isEmpty) return const [];

  final widths = List<double>.filled(columns.length, minWidth);
  final sample = rows.length < sampleRowCount ? rows.length : sampleRowCount;

  for (var c = 0; c < columns.length; c++) {
    var maxChars = columns[c].length;
    for (var r = 0; r < sample; r++) {
      if (c < rows[r].length && rows[r][c].length > maxChars) {
        maxChars = rows[r][c].length;
      }
    }
    widths[c] = (maxChars * 7.5 + 24).clamp(minWidth, maxWidth);
  }
  return widths;
}

/// Prefix sums: `offsets[i]` = sum of widths `[0, i)`.
@visibleForTesting
List<double> computeResultGridColumnOffsets(List<double> columnWidths) {
  final offsets = List<double>.filled(columnWidths.length + 1, 0);
  for (var i = 0; i < columnWidths.length; i++) {
    offsets[i + 1] = offsets[i] + columnWidths[i];
  }
  return offsets;
}

/// Visible column range for a horizontal viewport (with overscan).
@visibleForTesting
ResultGridColumnWindow computeVisibleColumnWindow({
  required List<double> columnWidths,
  required List<double> columnOffsets,
  required double scrollOffset,
  required double viewportWidth,
  int overscanColumns = ResultGridMetrics.columnOverscan,
}) {
  final n = columnWidths.length;
  if (n == 0) return ResultGridColumnWindow.empty;
  assert(columnOffsets.length == n + 1);

  final total = columnOffsets[n];
  if (viewportWidth <= 0) {
    return ResultGridColumnWindow(
      first: 0,
      last: n - 1,
      leadingWidth: 0,
      trailingWidth: 0,
    );
  }

  final start = scrollOffset.clamp(0.0, total);
  final end = (scrollOffset + viewportWidth).clamp(0.0, total);

  // First column with any pixel past [start]: smallest index where columnOffsets[first + 1] > start
  var first = 0;
  var low = 0;
  var high = n - 1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (columnOffsets[mid + 1] > start) {
      first = mid;
      high = mid - 1;
    } else {
      low = mid + 1;
    }
  }

  // Last column with any pixel before [end]: largest index where columnOffsets[last] < end
  var last = n - 1;
  low = 0;
  high = n - 1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (columnOffsets[mid] < end) {
      last = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  if (first > last) {
    first = last.clamp(0, n - 1);
  }

  first = (first - overscanColumns).clamp(0, n - 1);
  last = (last + overscanColumns).clamp(0, n - 1);

  return ResultGridColumnWindow(
    first: first,
    last: last,
    leadingWidth: columnOffsets[first],
    trailingWidth: total - columnOffsets[last + 1],
  );
}

/// Coordinate of a cell in [VirtualResultGrid].
@immutable
class ResultGridCellCoordinate {
  const ResultGridCellCoordinate(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultGridCellCoordinate &&
          row == other.row &&
          column == other.column;

  @override
  int get hashCode => Object.hash(row, column);
}

/// Rectangular cell selection range in [VirtualResultGrid].
@immutable
class ResultGridSelection {
  const ResultGridSelection({
    required this.startRow,
    required this.startColumn,
    required this.endRow,
    required this.endColumn,
  });

  factory ResultGridSelection.fromPoints({
    required ResultGridCellCoordinate anchor,
    required ResultGridCellCoordinate focus,
  }) {
    final minR = anchor.row < focus.row ? anchor.row : focus.row;
    final maxR = anchor.row > focus.row ? anchor.row : focus.row;
    final minC = anchor.column < focus.column ? anchor.column : focus.column;
    final maxC = anchor.column > focus.column ? anchor.column : focus.column;
    return ResultGridSelection(
      startRow: minR,
      startColumn: minC,
      endRow: maxR,
      endColumn: maxC,
    );
  }

  final int startRow;
  final int startColumn;
  final int endRow;
  final int endColumn;

  bool contains(int row, int column) =>
      row >= startRow &&
      row <= endRow &&
      column >= startColumn &&
      column <= endColumn;

  int get rowCount => endRow - startRow + 1;
  int get columnCount => endColumn - startColumn + 1;

  /// Formats selected cell values as a Tab-Separated Values (TSV) string.
  String toTsv(List<List<String>> rows) {
    if (rows.isEmpty) return '';
    final buffer = StringBuffer();
    for (var r = startRow; r <= endRow; r++) {
      if (r < 0 || r >= rows.length) continue;
      final rowData = rows[r];
      final cells = <String>[];
      for (var c = startColumn; c <= endColumn; c++) {
        cells.add(c < rowData.length ? rowData[c] : '');
      }
      buffer.writeln(cells.join('\t'));
    }
    return buffer.toString().trimRight();
  }

  /// Formats selected cell values as a CSV string.
  String toCsv(List<List<String>> rows) {
    if (rows.isEmpty) return '';
    final buffer = StringBuffer();
    for (var r = startRow; r <= endRow; r++) {
      if (r < 0 || r >= rows.length) continue;
      final rowData = rows[r];
      final cells = <String>[];
      for (var c = startColumn; c <= endColumn; c++) {
        final val = c < rowData.length ? rowData[c] : '';
        if (val.contains(',') || val.contains('"') || val.contains('\n')) {
          cells.add('"${val.replaceAll('"', '""')}"');
        } else {
          cells.add(val);
        }
      }
      buffer.writeln(cells.join(','));
    }
    return buffer.toString().trimRight();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultGridSelection &&
          startRow == other.startRow &&
          startColumn == other.startColumn &&
          endRow == other.endRow &&
          endColumn == other.endColumn;

  @override
  int get hashCode => Object.hash(startRow, startColumn, endRow, endColumn);
}

/// Sorting direction for [VirtualResultGrid].
enum ResultGridSortOrder {
  ascending,
  descending,
}

/// Sorts rows by the specified column index with natural numeric / temporal / lexicographic comparison.
List<List<String>> sortResultGridRows({
  required List<List<String>> rows,
  required int columnIndex,
  required ResultGridSortOrder order,
}) {
  if (rows.isEmpty || columnIndex < 0) return rows;
  final sorted = List<List<String>>.from(rows);

  sorted.sort((a, b) {
    final valA = columnIndex < a.length ? a[columnIndex] : '';
    final valB = columnIndex < b.length ? b[columnIndex] : '';

    final isNullA = valA == 'NULL' || valA.isEmpty;
    final isNullB = valB == 'NULL' || valB.isEmpty;
    if (isNullA && isNullB) return 0;
    if (isNullA) return 1;
    if (isNullB) return -1;

    final numA = num.tryParse(valA);
    final numB = num.tryParse(valB);
    int cmp;
    if (numA != null && numB != null) {
      cmp = numA.compareTo(numB);
    } else {
      final dtA = DateTime.tryParse(valA);
      final dtB = DateTime.tryParse(valB);
      if (dtA != null && dtB != null) {
        cmp = dtA.compareTo(dtB);
      } else {
        cmp = valA.toLowerCase().compareTo(valB.toLowerCase());
        if (cmp == 0) {
          cmp = valA.compareTo(valB);
        }
      }
    }

    return order == ResultGridSortOrder.ascending ? cmp : -cmp;
  });

  return sorted;
}

/// Virtualized read-only or interactive grid for SQL query results (rows + columns).
class VirtualResultGrid extends material.StatefulWidget {
  const VirtualResultGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.stagingBuffer,
    this.onRowSelected,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final DataGridStagingBuffer? stagingBuffer;
  final material.ValueChanged<int?>? onRowSelected;

  @override
  material.State<VirtualResultGrid> createState() => _VirtualResultGridState();
}

class _VirtualResultGridState extends material.State<VirtualResultGrid> {
  final _horizontalController = material.ScrollController();
  final _verticalController = material.ScrollController();
  final _focusNode = material.FocusNode();

  List<double> _columnWidths = const [];
  List<double> _columnOffsets = const [0];
  bool _widthsNeedUpdate = true;
  bool _userHasResized = false;
  double _scrollOffset = 0;

  int? _sortColumnIndex;
  ResultGridSortOrder? _sortOrder;
  List<List<String>> _sortedRows = const [];

  ResultGridCellCoordinate? _selectionAnchor;
  ResultGridSelection? _selection;
  ResultGridCellCoordinate? _editingCell;

  @override
  void initState() {
    super.initState();
    _horizontalController.addListener(_onHorizontalScroll);
    widget.stagingBuffer?.addListener(_onStagingBufferChanged);
    _updateSortedRows();
  }

  void _onStagingBufferChanged() {
    if (!mounted) return;
    setState(() {
      _updateSortedRows();
      _widthsNeedUpdate = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _widthsNeedUpdate = true;
  }

  @override
  void didUpdateWidget(VirtualResultGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stagingBuffer != widget.stagingBuffer) {
      oldWidget.stagingBuffer?.removeListener(_onStagingBufferChanged);
      widget.stagingBuffer?.addListener(_onStagingBufferChanged);
    }
    if (oldWidget.columns != widget.columns ||
        oldWidget.rows != widget.rows ||
        oldWidget.stagingBuffer != widget.stagingBuffer) {
      _widthsNeedUpdate = true;
      if (oldWidget.columns != widget.columns) {
        _userHasResized = false;
        _sortColumnIndex = null;
        _sortOrder = null;
        _selectionAnchor = null;
        _selection = null;
        _editingCell = null;
        widget.onRowSelected?.call(null);
      }
      _updateSortedRows();
    }
  }

  @override
  void dispose() {
    widget.stagingBuffer?.removeListener(_onStagingBufferChanged);
    _horizontalController.removeListener(_onHorizontalScroll);
    _horizontalController.dispose();
    _verticalController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing(int row, int column) {
    if (widget.stagingBuffer == null) return;
    if (row < 0 || row >= _sortedRows.length || column < 0 || column >= widget.columns.length) return;
    setState(() {
      _editingCell = ResultGridCellCoordinate(row, column);
      _selectionAnchor = _editingCell;
      _selection = ResultGridSelection(
        startRow: row,
        startColumn: column,
        endRow: row,
        endColumn: column,
      );
    });
  }

  void _commitEdit(
    int row,
    int column,
    String value, {
    bool moveNextCol = false,
    bool movePrevCol = false,
    bool moveNextRow = false,
  }) {
    if (widget.stagingBuffer != null) {
      widget.stagingBuffer!.setCell(row, column, value);
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
          _editingCell = ResultGridCellCoordinate(row - 1, widget.columns.length - 1);
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
      } else {
        _editingCell = null;
      }
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingCell = null;
    });
  }

  Future<void> _openInspector(int row, int column) async {
    if (row < 0 || row >= _sortedRows.length || column < 0 || column >= widget.columns.length) return;
    final colName = widget.columns[column];
    final currentVal = column < _sortedRows[row].length ? _sortedRows[row][column] : '';
    final result = await showGridCellInspectorDialog(
      context: context,
      columnName: colName,
      initialValue: currentVal,
      rowIndex: row,
    );
    if (result != null && widget.stagingBuffer != null) {
      widget.stagingBuffer!.setCell(row, column, result);
    }
  }

  void _onHorizontalScroll() {
    if (!_horizontalController.hasClients) return;
    final offset = _horizontalController.offset;
    if ((offset - _scrollOffset).abs() < 0.5) return;
    setState(() => _scrollOffset = offset);
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

  List<List<String>> get _baseRows =>
      widget.stagingBuffer?.effectiveRows ?? widget.rows;

  void _updateSortedRows() {
    final rows = _baseRows;
    if (_sortColumnIndex == null || _sortOrder == null) {
      _sortedRows = rows;
    } else {
      _sortedRows = sortResultGridRows(
        rows: rows,
        columnIndex: _sortColumnIndex!,
        order: _sortOrder!,
      );
    }
  }

  void _onCellTap(int row, int column, {bool isShift = false}) {
    _focusNode.requestFocus();
    widget.onRowSelected?.call(row);
    setState(() {
      final coord = ResultGridCellCoordinate(row, column);
      if (isShift && _selectionAnchor != null) {
        _selection = ResultGridSelection.fromPoints(
          anchor: _selectionAnchor!,
          focus: coord,
        );
      } else {
        _selectionAnchor = coord;
        _selection = ResultGridSelection(
          startRow: row,
          startColumn: column,
          endRow: row,
          endColumn: column,
        );
      }
    });
  }

  void _onCellSecondaryTap(int row, int column) {
    _focusNode.requestFocus();
    widget.onRowSelected?.call(row);
    if (_selection != null && _selection!.contains(row, column)) {
      _copySelection();
    } else {
      setState(() {
        _selectionAnchor = ResultGridCellCoordinate(row, column);
        _selection = ResultGridSelection(
          startRow: row,
          startColumn: column,
          endRow: row,
          endColumn: column,
        );
      });
      _copySelection();
    }
  }

  void _copySelection({bool asCsv = false}) {
    if (_selection == null) return;
    final text = asCsv
        ? _selection!.toCsv(_sortedRows)
        : _selection!.toTsv(_sortedRows);
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
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

  @override
  material.Widget build(material.BuildContext context) {
    if (_widthsNeedUpdate && !_userHasResized) {
      _columnWidths = _computeColumnWidths();
      _columnOffsets = computeResultGridColumnOffsets(_columnWidths);
      _widthsNeedUpdate = false;
    }
    final cs = Theme.of(context).colorScheme;
    final rowHeight = _scaledRowHeight(context);
    final headerHeight = _scaledHeaderHeight(context);

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
            widget.stagingBuffer!.toggleDeleteRow(_selection!.startRow);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.backspace,
          meta: true,
        ): () {
          if (widget.stagingBuffer != null && _selection != null) {
            widget.stagingBuffer!.toggleDeleteRow(_selection!.startRow);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
        ): () {
          if (widget.stagingBuffer != null && _selection != null) {
            widget.stagingBuffer!.revertRow(_selection!.startRow);
          }
        },
        const material.SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
        ): () {
          if (widget.stagingBuffer != null && _selection != null) {
            widget.stagingBuffer!.revertRow(_selection!.startRow);
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
            });
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
          LogicalKeyboardKey.keyN,
          alt: true,
        ): () {
          if (_selection != null && widget.stagingBuffer != null) {
            widget.stagingBuffer!.setCell(
              _selection!.startRow,
              _selection!.startColumn,
              'NULL',
            );
          }
        },
      },
      child: material.Focus(
        focusNode: _focusNode,
        child: material.RepaintBoundary(
          child: material.LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;

              var displayWidths = _columnWidths;
              var tableWidth = _tableWidth;
              if (!_userHasResized &&
                  tableWidth < availableWidth &&
                  _columnWidths.isNotEmpty) {
                final extraPerCol =
                    (availableWidth - tableWidth) / _columnWidths.length;
                displayWidths = [for (final w in _columnWidths) w + extraPerCol];
                tableWidth = availableWidth;
              } else if (tableWidth < availableWidth) {
                tableWidth = availableWidth;
              }

              final window = _columnWindow(displayWidths, availableWidth);

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
                        ),
                        material.Expanded(
                          child: material.Scrollbar(
                            controller: _verticalController,
                            thumbVisibility: true,
                            child: material.ListView.builder(
                              controller: _verticalController,
                              itemCount: _sortedRows.length,
                              itemExtent: rowHeight,
                              itemBuilder: (context, rowIndex) {
                                final row = _sortedRows[rowIndex];
                                final isEven = rowIndex.isEven;
                                return _DataRow(
                                  key: ValueKey('result-row-$rowIndex'),
                                  rowIndex: rowIndex,
                                  row: row,
                                  columnWidths: displayWidths,
                                  window: window,
                                  height: rowHeight,
                                  colorScheme: cs,
                                  striped: !isEven,
                                  selection: _selection,
                                  stagingBuffer: widget.stagingBuffer,
                                  editingCell: _editingCell,
                                  onCellTap: _onCellTap,
                                  onCellDoubleTap: _startEditing,
                                  onCellSecondaryTap: _onCellSecondaryTap,
                                  onCommitEdit: _commitEdit,
                                  onCancelEdit: _cancelEdit,
                                  onOpenInspector: _openInspector,
                                );
                              },
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

class _HeaderRow extends material.StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.columnWidths,
    required this.window,
    required this.height,
    required this.colorScheme,
    this.sortColumnIndex,
    this.sortOrder,
    this.onSortColumn,
    this.onResizeColumn,
  });

  final List<String> columns;
  final List<double> columnWidths;
  final ResultGridColumnWindow window;
  final double height;
  final ColorScheme colorScheme;
  final int? sortColumnIndex;
  final ResultGridSortOrder? sortOrder;
  final material.ValueChanged<int>? onSortColumn;
  final void Function(int index, double delta)? onResizeColumn;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      height: height,
      decoration: material.BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.35),
        border: material.Border(
          bottom: material.BorderSide(
            color: colorScheme.border.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: material.Row(
        children: [
          if (window.leadingWidth > 0)
            material.SizedBox(width: window.leadingWidth),
          for (var i = window.first; i <= window.last; i++)
            _HeaderCell(
              text: columns[i],
              width: columnWidths[i],
              colorScheme: colorScheme,
              sortOrder: sortColumnIndex == i ? sortOrder : null,
              onSort: onSortColumn != null ? () => onSortColumn!(i) : null,
              onResize: onResizeColumn != null
                  ? (delta) => onResizeColumn!(i, delta)
                  : null,
            ),
          if (window.trailingWidth > 0)
            material.SizedBox(width: window.trailingWidth),
        ],
      ),
    );
  }
}

class _HeaderCell extends material.StatelessWidget {
  const _HeaderCell({
    required this.text,
    required this.width,
    required this.colorScheme,
    this.sortOrder,
    this.onSort,
    this.onResize,
  });

  final String text;
  final double width;
  final ColorScheme colorScheme;
  final ResultGridSortOrder? sortOrder;
  final material.VoidCallback? onSort;
  final material.ValueChanged<double>? onResize;

  @override
  material.Widget build(material.BuildContext context) {
    final isSorted = sortOrder != null;
    final style = material.TextStyle(
      fontSize: 12,
      fontWeight: material.FontWeight.w600,
      color: isSorted ? colorScheme.primary : colorScheme.foreground,
    );

    return material.Container(
      width: width,
      height: double.infinity,
      decoration: material.BoxDecoration(
        border: material.Border(
          right: material.BorderSide(
            color: colorScheme.border.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: material.Stack(
        clipBehavior: material.Clip.none,
        children: [
          material.Positioned.fill(
            child: material.MouseRegion(
              cursor: onSort != null
                  ? material.SystemMouseCursors.click
                  : material.SystemMouseCursors.basic,
              child: material.GestureDetector(
                behavior: material.HitTestBehavior.opaque,
                onTap: onSort,
                child: material.Padding(
                  padding: const material.EdgeInsets.symmetric(horizontal: 10),
                  child: material.Row(
                    children: [
                      material.Expanded(
                        child: material.Text(
                          text,
                          style: style,
                          overflow: material.TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (sortOrder != null) ...[
                        const Gap(4),
                        material.Icon(
                          sortOrder == ResultGridSortOrder.ascending
                              ? material.Icons.arrow_upward_rounded
                              : material.Icons.arrow_downward_rounded,
                          size: 14,
                          color: colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onResize != null)
            material.Positioned(
              right: -4,
              top: 0,
              bottom: 0,
              width: 10,
              child: material.MouseRegion(
                cursor: material.SystemMouseCursors.resizeColumn,
                child: material.GestureDetector(
                  behavior: material.HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    onResize!(details.delta.dx);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DataRow extends material.StatelessWidget {
  const _DataRow({
    super.key,
    required this.rowIndex,
    required this.row,
    required this.columnWidths,
    required this.window,
    required this.height,
    required this.colorScheme,
    required this.striped,
    this.selection,
    this.stagingBuffer,
    this.editingCell,
    this.onCellTap,
    this.onCellDoubleTap,
    this.onCellSecondaryTap,
    this.onCommitEdit,
    this.onCancelEdit,
    this.onOpenInspector,
  });

  final int rowIndex;
  final List<String> row;
  final List<double> columnWidths;
  final ResultGridColumnWindow window;
  final double height;
  final ColorScheme colorScheme;
  final bool striped;
  final ResultGridSelection? selection;
  final DataGridStagingBuffer? stagingBuffer;
  final ResultGridCellCoordinate? editingCell;
  final void Function(int row, int col, {bool isShift})? onCellTap;
  final void Function(int row, int col)? onCellDoubleTap;
  final void Function(int row, int col)? onCellSecondaryTap;
  final void Function(
    int row,
    int col,
    String val, {
    bool moveNextCol,
    bool movePrevCol,
    bool moveNextRow,
  })? onCommitEdit;
  final material.VoidCallback? onCancelEdit;
  final void Function(int row, int col)? onOpenInspector;

  @override
  material.Widget build(material.BuildContext context) {
    final rowStatus = stagingBuffer?.getRowStatus(rowIndex) ?? StagedRowStatus.unchanged;

    return material.RepaintBoundary(
      child: material.SizedBox(
        height: height,
        child: material.Row(
          children: [
            if (window.leadingWidth > 0)
              material.SizedBox(width: window.leadingWidth),
            for (var c = window.first; c <= window.last; c++)
              _GridCell(
                row: rowIndex,
                column: c,
                text: c < row.length ? row[c] : '',
                width: columnWidths[c],
                colorScheme: colorScheme,
                striped: striped,
                rowStatus: rowStatus,
                cellStatus: stagingBuffer?.getCellStatus(rowIndex, c) ?? StagedCellStatus.clean,
                isSelected: selection?.contains(rowIndex, c) ?? false,
                isEditing: editingCell?.row == rowIndex && editingCell?.column == c,
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
                onTap: onCellTap,
                onDoubleTap: onCellDoubleTap,
                onSecondaryTap: onCellSecondaryTap,
                onCommitEdit: onCommitEdit,
                onCancelEdit: onCancelEdit,
                onOpenInspector: onOpenInspector,
              ),
            if (window.trailingWidth > 0)
              material.SizedBox(width: window.trailingWidth),
          ],
        ),
      ),
    );
  }
}

class _GridCell extends material.StatelessWidget {
  const _GridCell({
    required this.row,
    required this.column,
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
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.onCommitEdit,
    this.onCancelEdit,
    this.onOpenInspector,
  });

  final int row;
  final int column;
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
  final void Function(int row, int col, {bool isShift})? onTap;
  final void Function(int row, int col)? onDoubleTap;
  final void Function(int row, int col)? onSecondaryTap;
  final void Function(
    int row,
    int col,
    String val, {
    bool moveNextCol,
    bool movePrevCol,
    bool moveNextRow,
  })? onCommitEdit;
  final material.VoidCallback? onCancelEdit;
  final void Function(int row, int col)? onOpenInspector;

  @override
  material.Widget build(material.BuildContext context) {
    if (isEditing) {
      return GridCellEditor(
        initialValue: text,
        width: width,
        height: double.infinity,
        onCommit: (val, {moveNextCol = false, movePrevCol = false, moveNextRow = false}) {
          onCommitEdit?.call(
            row,
            column,
            val,
            moveNextCol: moveNextCol,
            movePrevCol: movePrevCol,
            moveNextRow: moveNextRow,
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

    final interactiveCell = material.GestureDetector(
      behavior: material.HitTestBehavior.opaque,
      onTap: () {
        final isShift = HardwareKeyboard.instance.isShiftPressed;
        onTap?.call(row, column, isShift: isShift);
      },
      onDoubleTap: () {
        onDoubleTap?.call(row, column);
      },
      onSecondaryTap: () {
        onSecondaryTap?.call(row, column);
      },
      child: cell,
    );

    if (text.length < ResultGridMetrics.tooltipMinLength) {
      return interactiveCell;
    }

    return material.Tooltip(
      message: text,
      waitDuration: kQueryaTooltipWait,
      child: interactiveCell,
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

