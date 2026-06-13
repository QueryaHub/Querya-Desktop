import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Layout metrics for [VirtualResultGrid].
abstract final class ResultGridMetrics {
  static const double rowHeight = 36;
  static const double headerHeight = 36;
  static const double minColumnWidth = 120;
  static const double maxColumnWidth = 280;
  static const int columnWidthSampleRows = 40;
  static const int tooltipMinLength = 48;
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

/// Virtualized read-only grid for SQL query results.
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
  bool _widthsNeedUpdate = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_widthsNeedUpdate) {
      _columnWidths = _computeColumnWidths();
      _widthsNeedUpdate = false;
    }
  }

  @override
  void didUpdateWidget(VirtualResultGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columns != widget.columns ||
        oldWidget.rows != widget.rows) {
      _widthsNeedUpdate = true;
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
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
    return _columnWidths.reduce((a, b) => a + b);
  }

  double _scaledRowHeight(material.BuildContext context) =>
      context.scaled(ResultGridMetrics.rowHeight);

  double _scaledHeaderHeight(material.BuildContext context) =>
      context.scaled(ResultGridMetrics.headerHeight);

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colCount = widget.columns.length;
    final rowHeight = _scaledRowHeight(context);
    final headerHeight = _scaledHeaderHeight(context);

    return material.RepaintBoundary(
      child: material.LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = _tableWidth > constraints.maxWidth
              ? _tableWidth
              : constraints.maxWidth;

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
                      columnWidths: _columnWidths,
                      height: headerHeight,
                      colorScheme: cs,
                    ),
                    material.Expanded(
                      child: material.Scrollbar(
                        controller: _verticalController,
                        thumbVisibility: true,
                        child: material.ListView.builder(
                          controller: _verticalController,
                          itemCount: widget.rows.length,
                          itemExtent: rowHeight,
                          itemBuilder: (context, rowIndex) {
                            final row = widget.rows[rowIndex];
                            final isEven = rowIndex.isEven;
                            return _DataRow(
                              key: ValueKey('result-row-$rowIndex'),
                              row: row,
                              columnWidths: _columnWidths,
                              columnCount: colCount,
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
    required this.height,
    required this.colorScheme,
  });

  final List<String> columns;
  final List<double> columnWidths;
  final double height;
  final ColorScheme colorScheme;

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
          for (var i = 0; i < columns.length; i++)
            _GridCell(
              text: columns[i],
              width: columnWidths[i],
              isHeader: true,
              colorScheme: colorScheme,
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
    required this.columnCount,
    required this.height,
    required this.colorScheme,
    required this.striped,
  });

  final List<String> row;
  final List<double> columnWidths;
  final int columnCount;
  final double height;
  final ColorScheme colorScheme;
  final bool striped;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
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
          for (var c = 0; c < columnCount; c++)
            _GridCell(
              text: c < row.length ? row[c] : '',
              width: columnWidths[c],
              colorScheme: colorScheme,
            ),
        ],
      ),
    );
  }
}

class _GridCell extends material.StatelessWidget {
  const _GridCell({
    required this.text,
    required this.width,
    required this.colorScheme,
    this.isHeader = false,
  });

  final String text;
  final double width;
  final ColorScheme colorScheme;
  final bool isHeader;

  @override
  material.Widget build(material.BuildContext context) {
    final isNull = !isHeader && text == 'NULL';
    final style = material.TextStyle(
      fontSize: isHeader ? 12 : 12,
      fontWeight:
          isHeader ? material.FontWeight.w600 : material.FontWeight.normal,
      fontFamily: isHeader ? null : 'monospace',
      color: isNull
          ? colorScheme.mutedForeground.withValues(alpha: 0.5)
          : (isHeader ? colorScheme.foreground : colorScheme.foreground),
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

    if (isHeader) return cell;

    return material.Tooltip(
      message: text.length >= ResultGridMetrics.tooltipMinLength ? text : '',
      waitDuration: const Duration(milliseconds: 400),
      child: material.GestureDetector(
        onSecondaryTap: () => Clipboard.setData(ClipboardData(text: text)),
        child: cell,
      ),
    );
  }
}
