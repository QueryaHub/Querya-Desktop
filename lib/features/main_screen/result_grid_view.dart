import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/ui/querya_tooltip.dart';
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

/// Virtualized read-only grid for SQL query results (rows + columns).
class VirtualResultGrid extends material.StatefulWidget {
  const VirtualResultGrid({
    super.key,
    required this.columns,
    required this.rows,
  });

  final List<String> columns;
  final List<List<String>> rows;

  @override
  material.State<VirtualResultGrid> createState() => _VirtualResultGridState();
}

class _VirtualResultGridState extends material.State<VirtualResultGrid> {
  final _horizontalController = material.ScrollController();
  final _verticalController = material.ScrollController();

  List<double> _columnWidths = const [];
  List<double> _columnOffsets = const [0];
  bool _widthsNeedUpdate = true;
  bool _userHasResized = false;
  double _scrollOffset = 0;

  int? _sortColumnIndex;
  ResultGridSortOrder? _sortOrder;
  List<List<String>> _sortedRows = const [];

  @override
  void initState() {
    super.initState();
    _horizontalController.addListener(_onHorizontalScroll);
    _updateSortedRows();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _widthsNeedUpdate = true;
  }

  @override
  void didUpdateWidget(VirtualResultGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columns != widget.columns || oldWidget.rows != widget.rows) {
      _widthsNeedUpdate = true;
      if (oldWidget.columns != widget.columns) {
        _userHasResized = false;
        _sortColumnIndex = null;
        _sortOrder = null;
      }
      _updateSortedRows();
    }
  }

  @override
  void dispose() {
    _horizontalController.removeListener(_onHorizontalScroll);
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
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

  void _updateSortedRows() {
    if (_sortColumnIndex == null || _sortOrder == null) {
      _sortedRows = widget.rows;
    } else {
      _sortedRows = sortResultGridRows(
        rows: widget.rows,
        columnIndex: _sortColumnIndex!,
        order: _sortOrder!,
      );
    }
  }

  List<double> _computeColumnWidths() {
    return computeResultGridColumnWidths(
      columns: widget.columns,
      rows: widget.rows,
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

    return material.RepaintBoundary(
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
                              row: row,
                              columnWidths: displayWidths,
                              window: window,
                              height: rowHeight,
                              colorScheme: cs,
                              striped: !isEven,
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
                  : material.MouseCursor.defer,
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
                      if (isSorted) ...[
                        const material.SizedBox(width: 4),
                        material.Icon(
                          sortOrder == ResultGridSortOrder.ascending
                              ? material.Icons.arrow_upward_rounded
                              : material.Icons.arrow_downward_rounded,
                          size: 13,
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
    required this.row,
    required this.columnWidths,
    required this.window,
    required this.height,
    required this.colorScheme,
    required this.striped,
  });

  final List<String> row;
  final List<double> columnWidths;
  final ResultGridColumnWindow window;
  final double height;
  final ColorScheme colorScheme;
  final bool striped;

  @override
  material.Widget build(material.BuildContext context) {
    return material.RepaintBoundary(
      child: material.Container(
        height: height,
        decoration: material.BoxDecoration(
          color: striped
              ? colorScheme.muted.withValues(alpha: 0.12)
              : material.Colors.transparent,
          border: material.Border(
            bottom: material.BorderSide(
              color: colorScheme.border.withValues(alpha: 0.15),
            ),
          ),
        ),
        child: material.Row(
          children: [
            if (window.leadingWidth > 0)
              material.SizedBox(width: window.leadingWidth),
            for (var c = window.first; c <= window.last; c++)
              _GridCell(
                text: c < row.length ? row[c] : '',
                width: columnWidths[c],
                colorScheme: colorScheme,
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
    required this.text,
    required this.width,
    required this.colorScheme,
  });

  final String text;
  final double width;
  final ColorScheme colorScheme;

  @override
  material.Widget build(material.BuildContext context) {
    final isNull = text == 'NULL';
    final style = material.TextStyle(
      fontSize: 12,
      fontWeight: material.FontWeight.normal,
      fontFamily: 'monospace',
      color: isNull
          ? colorScheme.mutedForeground.withValues(alpha: 0.5)
          : colorScheme.foreground,
      fontStyle: isNull ? material.FontStyle.italic : material.FontStyle.normal,
    );

    final cell = material.Container(
      width: width,
      padding: const material.EdgeInsets.symmetric(horizontal: 10),
      alignment: material.Alignment.centerLeft,
      decoration: material.BoxDecoration(
        border: material.Border(
          right: material.BorderSide(
            color: colorScheme.border.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: material.Text(
        text,
        style: style,
        overflow: material.TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );

    final interactiveCell = material.GestureDetector(
      onSecondaryTap: () => Clipboard.setData(ClipboardData(text: text)),
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
