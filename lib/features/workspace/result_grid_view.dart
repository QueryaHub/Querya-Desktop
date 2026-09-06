import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HardwareKeyboard, LogicalKeyboardKey;
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/ui/querya_tooltip.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/grid_cell_editor.dart';
import 'package:querya_desktop/features/workspace/grid_cell_popover_inspector.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Layout metrics for [VirtualResultGrid].
abstract final class ResultGridMetrics {
  static const double rowHeight = 36;
  static const double headerHeight = 36;
  static const double minColumnWidth = 56;
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
    final headerWidth = columns[c].length * 7.5 + 38.0;
    var maxRowChars = 0;
    for (var r = 0; r < sample; r++) {
      if (c < rows[r].length && rows[r][c].length > maxRowChars) {
        maxRowChars = rows[r][c].length;
      }
    }
    final contentWidth = maxRowChars * 7.5 + 24.0;
    final naturalWidth = math.max(headerWidth, contentWidth);
    widths[c] = naturalWidth.clamp(minWidth, maxWidth);
  }
  return widths;
}

/// Distributes spare viewport width adaptively to columns that benefit from expansion,
/// avoiding artificial stretching of compact columns.
List<double> distributeResultGridSpareWidth({
  required List<double> columnWidths,
  required List<String> columns,
  required List<List<String>> rows,
  required double availableWidth,
  double maxColumnWidth = ResultGridMetrics.maxColumnWidth,
  int sampleRowCount = ResultGridMetrics.columnWidthSampleRows,
}) {
  if (columnWidths.isEmpty || columns.isEmpty) return columnWidths;

  final totalInitial = columnWidths.fold<double>(0.0, (sum, w) => sum + w);
  final spare = availableWidth - totalInitial;
  if (spare <= 0.5) return columnWidths;

  final sample = rows.length < sampleRowCount ? rows.length : sampleRowCount;
  final desiredWidths = List<double>.filled(columns.length, 0);

  for (var c = 0; c < columns.length; c++) {
    final headerWidth = columns[c].length * 7.5 + 38.0;
    var maxRowChars = 0;
    for (var r = 0; r < sample; r++) {
      if (c < rows[r].length && rows[r][c].length > maxRowChars) {
        maxRowChars = rows[r][c].length;
      }
    }
    final contentWidth = maxRowChars * 7.5 + 24.0;
    desiredWidths[c] = math.max(headerWidth, contentWidth);
  }

  // Deficit columns: columns whose desired width exceeds the clamped initial width
  final deficits = List<double>.filled(columns.length, 0);
  var totalDeficit = 0.0;
  for (var c = 0; c < columns.length; c++) {
    if (desiredWidths[c] > columnWidths[c]) {
      final def = desiredWidths[c] - columnWidths[c];
      deficits[c] = def;
      totalDeficit += def;
    }
  }

  final result = List<double>.from(columnWidths);

  if (totalDeficit > 0) {
    if (spare <= totalDeficit) {
      final ratio = spare / totalDeficit;
      for (var c = 0; c < columns.length; c++) {
        if (deficits[c] > 0) {
          result[c] += deficits[c] * ratio;
        }
      }
      return result;
    } else {
      for (var c = 0; c < columns.length; c++) {
        if (deficits[c] > 0) {
          result[c] += deficits[c];
        }
      }
      final remainingSpare = spare - totalDeficit;
      _distributeRemainingSpare(result, remainingSpare);
      return result;
    }
  } else {
    _distributeRemainingSpare(result, spare);
    return result;
  }
}

void _distributeRemainingSpare(List<double> widths, double spare) {
  final weights = List<double>.filled(widths.length, 0);
  var totalWeight = 0.0;
  for (var i = 0; i < widths.length; i++) {
    if (widths[i] > 110) {
      final w = widths[i] - 100;
      weights[i] = w;
      totalWeight += w;
    }
  }

  if (totalWeight <= 0) {
    return;
  }

  final ratio = spare / totalWeight;
  for (var i = 0; i < widths.length; i++) {
    if (weights[i] > 0) {
      final extra = math.min(weights[i] * ratio, 120.0);
      widths[i] += extra;
    }
  }
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
  /// If [columns] is provided, prepends a header row for the selected column range.
  String toTsv(List<List<String>> rows, {List<String>? columns}) {
    if (rows.isEmpty) return '';
    final buffer = StringBuffer();
    if (columns != null && columns.isNotEmpty) {
      final headerCells = <String>[];
      for (var c = startColumn; c <= endColumn; c++) {
        headerCells.add(c < columns.length ? columns[c] : '');
      }
      buffer.writeln(headerCells.join('\t'));
    }
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
  /// If [columns] is provided, prepends a header row for the selected column range.
  String toCsv(List<List<String>> rows, {List<String>? columns}) {
    if (rows.isEmpty) return '';
    final buffer = StringBuffer();
    if (columns != null && columns.isNotEmpty) {
      final headerCells = <String>[];
      for (var c = startColumn; c <= endColumn; c++) {
        final col = c < columns.length ? columns[c] : '';
        headerCells.add(_escapeCsv(col));
      }
      buffer.writeln(headerCells.join(','));
    }
    for (var r = startRow; r <= endRow; r++) {
      if (r < 0 || r >= rows.length) continue;
      final rowData = rows[r];
      final cells = <String>[];
      for (var c = startColumn; c <= endColumn; c++) {
        final val = c < rowData.length ? rowData[c] : '';
        cells.add(_escapeCsv(val));
      }
      buffer.writeln(cells.join(','));
    }
    return buffer.toString().trimRight();
  }

  /// Formats selected cell values as a formatted JSON string.
  /// Returns a JSON object for single-row selection, or a JSON array for multi-row selection.
  String toJson(List<String> columns, List<List<String>> rows) {
    if (rows.isEmpty || columns.isEmpty) return '[]';
    final result = <Map<String, dynamic>>[];
    for (var r = startRow; r <= endRow; r++) {
      if (r < 0 || r >= rows.length) continue;
      final rowData = rows[r];
      final map = <String, dynamic>{};
      for (var c = startColumn; c <= endColumn; c++) {
        final colName = c < columns.length ? columns[c] : 'col_$c';
        final val = c < rowData.length ? rowData[c] : '';
        if (val == 'NULL') {
          map[colName] = null;
        } else if (int.tryParse(val) != null) {
          map[colName] = int.parse(val);
        } else if (double.tryParse(val) != null) {
          map[colName] = double.parse(val);
        } else if (val.toLowerCase() == 'true') {
          map[colName] = true;
        } else if (val.toLowerCase() == 'false') {
          map[colName] = false;
        } else {
          map[colName] = val;
        }
      }
      result.add(map);
    }
    if (result.length == 1) {
      return const JsonEncoder.withIndent('  ').convert(result.first);
    }
    return const JsonEncoder.withIndent('  ').convert(result);
  }

  static String _escapeCsv(String val) {
    if (val.contains(',') || val.contains('"') || val.contains('\n') || val.contains('\r')) {
      return '"${val.replaceAll('"', '""')}"';
    }
    return val;
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

enum _SortKeyType { nullOrEmpty, numeric, dateTime, string }

class _SortKey implements Comparable<_SortKey> {
  final _SortKeyType type;
  final num? numVal;
  final DateTime? dtVal;
  final String strLower;
  final String strRaw;

  _SortKey._({
    required this.type,
    this.numVal,
    this.dtVal,
    this.strLower = '',
    this.strRaw = '',
  });

  factory _SortKey.parse(String val) {
    if (val == 'NULL' || val.isEmpty) {
      return _SortKey._(type: _SortKeyType.nullOrEmpty);
    }
    final n = num.tryParse(val);
    if (n != null) {
      return _SortKey._(type: _SortKeyType.numeric, numVal: n, strRaw: val);
    }
    final dt = DateTime.tryParse(val);
    if (dt != null) {
      return _SortKey._(type: _SortKeyType.dateTime, dtVal: dt, strRaw: val);
    }
    return _SortKey._(
      type: _SortKeyType.string,
      strLower: val.toLowerCase(),
      strRaw: val,
    );
  }

  @override
  int compareTo(_SortKey other) {
    if (type == _SortKeyType.nullOrEmpty && other.type == _SortKeyType.nullOrEmpty) {
      return 0;
    }
    if (type == _SortKeyType.nullOrEmpty) return 1;
    if (other.type == _SortKeyType.nullOrEmpty) return -1;

    if (type == _SortKeyType.numeric && other.type == _SortKeyType.numeric) {
      return numVal!.compareTo(other.numVal!);
    }
    if (type == _SortKeyType.dateTime && other.type == _SortKeyType.dateTime) {
      return dtVal!.compareTo(other.dtVal!);
    }

    final aLower = type == _SortKeyType.string ? strLower : strRaw.toLowerCase();
    final bLower = other.type == _SortKeyType.string ? other.strLower : other.strRaw.toLowerCase();
    final cmp = aLower.compareTo(bLower);
    if (cmp != 0) return cmp;

    return strRaw.compareTo(other.strRaw);
  }
}

/// Result of sorting rows in [VirtualResultGrid], preserving model indices.
class SortedResultGridData {
  final List<List<String>> rows;
  final List<int> sortedToModelIndices;

  const SortedResultGridData({
    required this.rows,
    required this.sortedToModelIndices,
  });
}

/// Sorts rows by the specified column index with natural numeric / temporal / lexicographic comparison.
/// Uses Schwartzian transform (Decorate-Sort-Undecorate) to precompute sort keys in O(N) time.
/// Returns [SortedResultGridData] containing sorted rows and their corresponding model indices.
SortedResultGridData sortResultGridRowsWithIndices({
  required List<List<String>> rows,
  required int columnIndex,
  required ResultGridSortOrder order,
}) {
  if (rows.isEmpty || columnIndex < 0) {
    return SortedResultGridData(
      rows: rows,
      sortedToModelIndices: List<int>.generate(rows.length, (i) => i, growable: false),
    );
  }
  final n = rows.length;

  final keys = List<_SortKey>.generate(n, (i) {
    final row = rows[i];
    final val = columnIndex < row.length ? row[columnIndex] : '';
    return _SortKey.parse(val);
  }, growable: false);

  final indices = List<int>.generate(n, (i) => i, growable: false);

  indices.sort((a, b) {
    final cmp = keys[a].compareTo(keys[b]);
    return order == ResultGridSortOrder.ascending ? cmp : -cmp;
  });

  final sortedRows = List<List<String>>.generate(n, (i) => rows[indices[i]], growable: false);
  return SortedResultGridData(
    rows: sortedRows,
    sortedToModelIndices: indices,
  );
}

/// Sorts rows by the specified column index with natural numeric / temporal / lexicographic comparison.
List<List<String>> sortResultGridRows({
  required List<List<String>> rows,
  required int columnIndex,
  required ResultGridSortOrder order,
}) {
  return sortResultGridRowsWithIndices(
    rows: rows,
    columnIndex: columnIndex,
    order: order,
  ).rows;
}

/// Virtualized read-only or interactive grid for SQL query results (rows + columns).
class VirtualResultGrid extends material.StatefulWidget {
  const VirtualResultGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.stagingBuffer,
    this.onRowSelected,
    this.onSelectionValuesChanged,
    this.onCellFocused,
    this.onFilterRequested,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final DataGridStagingBuffer? stagingBuffer;
  final material.ValueChanged<int?>? onRowSelected;
  final material.ValueChanged<List<String>>? onSelectionValuesChanged;
  final void Function(String columnName, String cellValue, int rowIndex)? onCellFocused;
  final void Function(String filterExpression)? onFilterRequested;

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
  List<int> _sortedToModelIndices = const [];

  ResultGridCellCoordinate? _selectionAnchor;
  ResultGridCellCoordinate? _selectionFocus;
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
        _selectionFocus = null;
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
    _sortedRows = const [];
    _sortedToModelIndices = const [];
    _columnWidths = const [];
    _columnOffsets = const [0];
    super.dispose();
  }

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

  void _onColumnAutoFit(int index) {
    if (index < 0 ||
        index >= widget.columns.length ||
        index >= _columnWidths.length) {
      return;
    }
    final headerWidth = widget.columns[index].length * 7.5 + 38.0;
    var maxRowChars = 0;
    final sampleCount = math.min(_baseRows.length, 200);
    for (var r = 0; r < sampleCount; r++) {
      if (index < _baseRows[r].length &&
          _baseRows[r][index].length > maxRowChars) {
        maxRowChars = _baseRows[r][index].length;
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

  List<List<String>> get _baseRows =>
      widget.stagingBuffer?.effectiveRows ?? widget.rows;

  void _updateSortedRows() {
    final rows = _baseRows;
    if (_sortColumnIndex == null || _sortOrder == null) {
      _sortedRows = rows;
      _sortedToModelIndices = List<int>.generate(rows.length, (i) => i, growable: false);
    } else {
      final sortedData = sortResultGridRowsWithIndices(
        rows: rows,
        columnIndex: _sortColumnIndex!,
        order: _sortOrder!,
      );
      _sortedRows = sortedData.rows;
      _sortedToModelIndices = sortedData.sortedToModelIndices;
    }
  }

  void _notifySelectionAndFocus() {
    if (widget.onSelectionValuesChanged != null) {
      if (_selection == null) {
        widget.onSelectionValuesChanged!(const []);
      } else {
        final rows = _sortedRows;
        final values = <String>[];
        for (var r = _selection!.startRow; r <= _selection!.endRow; r++) {
          if (r >= 0 && r < rows.length) {
            for (var c = _selection!.startColumn; c <= _selection!.endColumn; c++) {
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

  void _onCellTap(int row, int column, {bool isShift = false}) {
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

  void _copySelection({bool withHeaders = false, bool asCsv = false, bool asJson = false}) {
    if (_selection == null) return;
    _copySelectionData(
      _selection!,
      withHeaders: withHeaders,
      asCsv: asCsv,
      asJson: asJson,
    );
  }

  void _handleCopyCell(
    int row,
    int column, {
    bool withHeaders = false,
    bool asCsv = false,
    bool asJson = false,
  }) {
    final sel = (_selection != null && _selection!.contains(row, column))
        ? _selection!
        : ResultGridSelection(
            startRow: row,
            startColumn: column,
            endRow: row,
            endColumn: column,
          );
    _copySelectionData(
      sel,
      withHeaders: withHeaders,
      asCsv: asCsv,
      asJson: asJson,
    );
  }

  void _copySelectionData(
    ResultGridSelection sel, {
    bool withHeaders = false,
    bool asCsv = false,
    bool asJson = false,
  }) {
    if (_sortedRows.isEmpty) return;
    String text;
    if (asJson) {
      text = sel.toJson(widget.columns, _sortedRows);
    } else if (asCsv) {
      text = sel.toCsv(
        _sortedRows,
        columns: withHeaders ? widget.columns : null,
      );
    } else {
      text = sel.toTsv(
        _sortedRows,
        columns: withHeaders ? widget.columns : null,
      );
    }
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
    }
  }

  void _handleFilterByValue(int row, int col, {required bool invert}) {
    if (widget.onFilterRequested == null) return;
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
        : ResultGridSelection(startRow: row, startColumn: col, endRow: row, endColumn: col);
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
        : ResultGridSelection(startRow: row, startColumn: col, endRow: row, endColumn: col);
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
        : ResultGridSelection(startRow: row, startColumn: col, endRow: row, endColumn: col);
    for (var r = sel.startRow; r <= sel.endRow; r++) {
      final modelRow = _toModelRowIndex(r);
      for (var c = sel.startColumn; c <= sel.endColumn; c++) {
        widget.stagingBuffer!.revertCell(modelRow, c);
      }
    }
  }

  void _handleDuplicateRow(int row) {
    if (widget.stagingBuffer == null || row >= _sortedRows.length) return;
    final rowData = _sortedRows[row];
    widget.stagingBuffer!.addRow(List<String>.from(rowData));
  }

  void _handleToggleDeleteRow(int row) {
    if (widget.stagingBuffer == null || row >= _sortedRows.length) return;
    widget.stagingBuffer!.toggleDeleteRow(_toModelRowIndex(row));
  }

  void _handleRevertRow(int row) {
    if (widget.stagingBuffer == null || row >= _sortedRows.length) return;
    widget.stagingBuffer!.revertRow(_toModelRowIndex(row));
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

              var displayWidths = _columnWidths;
              var tableWidth = _tableWidth;
              if (!_userHasResized &&
                  tableWidth < availableWidth &&
                  _columnWidths.isNotEmpty) {
                displayWidths = distributeResultGridSpareWidth(
                  columnWidths: _columnWidths,
                  columns: widget.columns,
                  rows: _baseRows,
                  availableWidth: availableWidth,
                  maxColumnWidth:
                      context.scaled(ResultGridMetrics.maxColumnWidth),
                );
                final distributedWidth =
                    displayWidths.fold<double>(0.0, (sum, w) => sum + w);
                tableWidth = math.max(distributedWidth, availableWidth);
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
                          onAutoFitColumn: _onColumnAutoFit,
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
                                  modelRowIndex: _toModelRowIndex(rowIndex),
                                  row: row,
                                  columns: widget.columns,
                                  columnWidths: displayWidths,
                                  window: window,
                                  height: rowHeight,
                                  colorScheme: cs,
                                  striped: !isEven,
                                  selection: _selection,
                                  stagingBuffer: widget.stagingBuffer,
                                  editingCell: _editingCell,
                                  canFilter: widget.onFilterRequested != null,
                                  onCellTap: _onCellTap,
                                  onCellDoubleTap: _startEditing,
                                  onCellSecondaryTap: _onCellSecondaryTap,
                                  onCommitEdit: _commitEdit,
                                  onCancelEdit: _cancelEdit,
                                  onOpenInspector: _openInspector,
                                  onCopyCell: _handleCopyCell,
                                  onFilterByValue: _handleFilterByValue,
                                  onFilterComparison: _handleFilterComparison,
                                  onSetNull: _handleSetNull,
                                  onSetEmpty: _handleSetEmpty,
                                  onRevertCell: _handleRevertCell,
                                  onDuplicateRow: _handleDuplicateRow,
                                  onToggleDeleteRow: _handleToggleDeleteRow,
                                  onRevertRow: _handleRevertRow,
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
    this.onAutoFitColumn,
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
  final void Function(int index)? onAutoFitColumn;

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
              onAutoFit: onAutoFitColumn != null
                  ? () => onAutoFitColumn!(i)
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
    this.onAutoFit,
  });

  final String text;
  final double width;
  final ColorScheme colorScheme;
  final ResultGridSortOrder? sortOrder;
  final material.VoidCallback? onSort;
  final material.ValueChanged<double>? onResize;
  final material.VoidCallback? onAutoFit;

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
                        child: material.Tooltip(
                          message: text,
                          waitDuration: kQueryaTooltipWait,
                          child: material.Text(
                            text,
                            style: style,
                            overflow: material.TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
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
          if (onResize != null || onAutoFit != null)
            material.Positioned(
              right: -5,
              top: 0,
              bottom: 0,
              width: 12,
              child: material.MouseRegion(
                cursor: material.SystemMouseCursors.resizeColumn,
                child: material.GestureDetector(
                  behavior: material.HitTestBehavior.translucent,
                  onDoubleTap: onAutoFit,
                  onHorizontalDragUpdate: onResize != null
                      ? (details) => onResize!(details.delta.dx)
                      : null,
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
    this.editingCell,
    this.canFilter = false,
    this.onCellTap,
    this.onCellDoubleTap,
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
  final ResultGridCellCoordinate? editingCell;
  final bool canFilter;
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
  final void Function(int row, int col, {required bool invert})? onFilterByValue;
  final void Function(int row, int col, String operator)? onFilterComparison;
  final void Function(int row, int col)? onSetNull;
  final void Function(int row, int col)? onSetEmpty;
  final void Function(int row, int col)? onRevertCell;
  final void Function(int row)? onDuplicateRow;
  final void Function(int row)? onToggleDeleteRow;
  final void Function(int row)? onRevertRow;

  @override
  material.Widget build(material.BuildContext context) {
    final rowStatus = stagingBuffer?.getRowStatus(modelRowIndex) ?? StagedRowStatus.unchanged;

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
                columnName: c < columns.length ? columns[c] : '',
                text: c < row.length ? row[c] : '',
                width: columnWidths[c],
                colorScheme: colorScheme,
                striped: striped,
                rowStatus: rowStatus,
                cellStatus: stagingBuffer?.getCellStatus(modelRowIndex, c) ?? StagedCellStatus.clean,
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
                canFilter: canFilter,
                hasStagingBuffer: stagingBuffer != null,
                onTap: onCellTap,
                onDoubleTap: onCellDoubleTap,
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
    this.onTap,
    this.onDoubleTap,
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
  final void Function(int row, int col, {required bool invert})? onFilterByValue;
  final void Function(int row, int col, String operator)? onFilterComparison;
  final void Function(int row, int col)? onSetNull;
  final void Function(int row, int col)? onSetEmpty;
  final void Function(int row, int col)? onRevertCell;
  final void Function(int row)? onDuplicateRow;
  final void Function(int row)? onToggleDeleteRow;
  final void Function(int row)? onRevertRow;

  List<MenuItem> _buildContextMenuItems(material.BuildContext context) {
    final preview = text.length > 24 ? '${text.substring(0, 22)}…' : text;
    final isNull = text == 'NULL';
    final numVal = num.tryParse(text);

    return [
      MenuButton(
        leading: const material.Icon(material.Icons.content_copy_rounded, size: 16),
        trailing: const material.Text('Ctrl+C', style: material.TextStyle(fontSize: 11)),
        onPressed: (_) => onCopyCell?.call(row, column),
        child: const material.Text('Copy Value'),
      ),
      MenuButton(
        leading: const material.Icon(material.Icons.table_chart_outlined, size: 16),
        trailing: const material.Text('Ctrl+Shift+C', style: material.TextStyle(fontSize: 11)),
        onPressed: (_) => onCopyCell?.call(row, column, withHeaders: true),
        child: const material.Text('Copy with Headers'),
      ),
      MenuButton(
        leading: const material.Icon(material.Icons.data_object_rounded, size: 16),
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
          leading: const material.Icon(material.Icons.filter_alt_outlined, size: 16),
          onPressed: (_) => onFilterByValue?.call(row, column, invert: false),
          child: material.Text(
            isNull
                ? 'Filter by NULL ($columnName IS NULL)'
                : 'Filter by Value ($columnName = $preview)',
          ),
        ),
        MenuButton(
          leading: const material.Icon(material.Icons.filter_alt_off_outlined, size: 16),
          onPressed: (_) => onFilterByValue?.call(row, column, invert: true),
          child: material.Text(
            isNull
                ? 'Filter Out NULL ($columnName IS NOT NULL)'
                : 'Filter Out ($columnName != $preview)',
          ),
        ),
        if (numVal != null) ...[
          MenuButton(
            leading: const material.Icon(material.Icons.chevron_right_rounded, size: 16),
            onPressed: (_) => onFilterComparison?.call(row, column, '>'),
            child: material.Text('Filter > $text ($columnName > $text)'),
          ),
          MenuButton(
            leading: const material.Icon(material.Icons.chevron_left_rounded, size: 16),
            onPressed: (_) => onFilterComparison?.call(row, column, '<'),
            child: material.Text('Filter < $text ($columnName < $text)'),
          ),
        ],
      ],
      const MenuDivider(),
      MenuButton(
        leading: const material.Icon(material.Icons.visibility_outlined, size: 16),
        trailing: const material.Text('Ctrl+I', style: material.TextStyle(fontSize: 11)),
        onPressed: (_) => onOpenInspector?.call(row, column),
        child: const material.Text('Inspect Cell Value…'),
      ),
      if (hasStagingBuffer) ...[
        MenuButton(
          leading: const material.Icon(material.Icons.remove_circle_outline_rounded, size: 16),
          trailing: const material.Text('Alt+N', style: material.TextStyle(fontSize: 11)),
          onPressed: (_) => onSetNull?.call(row, column),
          child: const material.Text('Set NULL'),
        ),
        MenuButton(
          leading: const material.Icon(material.Icons.format_clear_rounded, size: 16),
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
          leading: const material.Icon(material.Icons.content_paste_go_rounded, size: 16),
          trailing: const material.Text('Ctrl+D', style: material.TextStyle(fontSize: 11)),
          onPressed: (_) => onDuplicateRow?.call(row),
          child: const material.Text('Duplicate Row'),
        ),
        MenuButton(
          leading: material.Icon(
            rowStatus == StagedRowStatus.deleted
                ? material.Icons.restore_from_trash_rounded
                : material.Icons.delete_outline_rounded,
            size: 16,
            color: rowStatus == StagedRowStatus.deleted ? null : colorScheme.destructive,
          ),
          onPressed: (_) => onToggleDeleteRow?.call(row),
          child: material.Text(
            rowStatus == StagedRowStatus.deleted ? 'Restore Deleted Row' : 'Delete Row',
            style: material.TextStyle(
              color: rowStatus == StagedRowStatus.deleted ? null : colorScheme.destructive,
            ),
          ),
        ),
        if (rowStatus == StagedRowStatus.modified || rowStatus == StagedRowStatus.deleted)
          MenuButton(
            leading: const material.Icon(material.Icons.restore_rounded, size: 16),
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
        onCommit: (val, {moveNextCol = false, movePrevCol = false, moveNextRow = false, movePrevRow = false}) {
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

    final interactiveCell = material.GestureDetector(
      behavior: material.HitTestBehavior.opaque,
      onTap: () {
        final isShift = HardwareKeyboard.instance.isShiftPressed;
        onTap?.call(row, column, isShift: isShift);
      },
      onDoubleTap: () {
        onDoubleTap?.call(row, column);
      },
      child: cell,
    );

    material.Widget content = interactiveCell;
    if (text.length >= ResultGridMetrics.tooltipMinLength) {
      content = material.Tooltip(
        message: text,
        waitDuration: kQueryaTooltipWait,
        child: content,
      );
    }

    return material.Listener(
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton) {
          onSecondaryTap?.call(row, column);
        }
      },
      child: ContextMenu(
        items: _buildContextMenuItems(context),
        child: content,
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

