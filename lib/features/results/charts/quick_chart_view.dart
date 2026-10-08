import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/results/charts/chart_data.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Saves rendered chart PNG bytes; replaceable in tests.
typedef ChartPngSaver = Future<void> Function(Uint8List png);

Future<void> _defaultPngSaver(Uint8List png) async {
  final location = await getSaveLocation(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PNG', extensions: ['png']),
    ],
    suggestedName: 'chart.png',
  );
  if (location == null) return;
  await XFile.fromData(png, mimeType: 'image/png', name: 'chart.png')
      .saveTo(location.path);
}

/// 1-click chart tab: pick X / Y columns and a chart type, export as PNG.
class QuickChartView extends material.StatefulWidget {
  const QuickChartView({
    super.key,
    required this.columns,
    required this.rows,
    this.onSavePng,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final ChartPngSaver? onSavePng;

  @override
  material.State<QuickChartView> createState() => _QuickChartViewState();
}

class _QuickChartViewState extends material.State<QuickChartView> {
  final _boundaryKey = material.GlobalKey();
  QuickChartType _type = QuickChartType.bar;
  int? _labelCol;
  int? _valueCol;
  List<int> _numeric = const [];

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(QuickChartView old) {
    super.didUpdateWidget(old);
    if (old.columns != widget.columns || old.rows != widget.rows) {
      _recompute();
    }
  }

  void _recompute() {
    _numeric = ChartData.numericColumns(widget.columns, widget.rows);
    if (_numeric.isEmpty) {
      _valueCol = null;
      _labelCol = null;
      return;
    }
    if (_valueCol == null || !_numeric.contains(_valueCol)) {
      _valueCol = _numeric.last;
    }
    if (_labelCol != null && _labelCol! >= widget.columns.length) {
      _labelCol = null;
    }
    _labelCol ??= _defaultLabel();
  }

  int? _defaultLabel() {
    for (var i = 0; i < widget.columns.length; i++) {
      if (i != _valueCol && !_numeric.contains(i)) return i;
    }
    for (var i = 0; i < widget.columns.length; i++) {
      if (i != _valueCol) return i;
    }
    return null;
  }

  Future<void> _export() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    await (widget.onSavePng ?? _defaultPngSaver)(data.buffer.asUint8List());
  }

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    if (_valueCol == null) {
      return material.Center(
        child: Text(
          'No numeric column to chart',
          style: material.TextStyle(color: wb.mutedForeground),
        ),
      );
    }
    final points = ChartData.build(
      rows: widget.rows,
      labelColumn: _labelCol,
      valueColumn: _valueCol!,
      type: _type,
    );
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Padding(
          padding: const material.EdgeInsets.all(8),
          child: material.Row(
            children: [
              material.SegmentedButton<QuickChartType>(
                segments: const [
                  material.ButtonSegment(
                      value: QuickChartType.bar, label: Text('Bar')),
                  material.ButtonSegment(
                      value: QuickChartType.line, label: Text('Line')),
                  material.ButtonSegment(
                      value: QuickChartType.pie, label: Text('Pie')),
                ],
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const material.SizedBox(width: 12),
              const Text('X'),
              const material.SizedBox(width: 6),
              QueryaDropdown<int>(
                key: const material.ValueKey('chart_x'),
                value: _labelCol ?? -1,
                width: 160,
                items: [
                  const QueryaDropdownItem(value: -1, label: '(row #)'),
                  for (var i = 0; i < widget.columns.length; i++)
                    QueryaDropdownItem(value: i, label: widget.columns[i]),
                ],
                onSelected: (v) =>
                    setState(() => _labelCol = (v == null || v < 0) ? null : v),
              ),
              const material.SizedBox(width: 12),
              const Text('Y'),
              const material.SizedBox(width: 6),
              QueryaDropdown<int>(
                key: const material.ValueKey('chart_y'),
                value: _valueCol!,
                width: 160,
                items: [
                  for (final i in _numeric)
                    QueryaDropdownItem(value: i, label: widget.columns[i]),
                ],
                onSelected: (v) => setState(() => _valueCol = v ?? _valueCol),
              ),
              const material.Spacer(),
              material.IconButton(
                key: const material.ValueKey('chart_export'),
                tooltip: 'Export PNG',
                icon: const material.Icon(material.Icons.image_outlined),
                onPressed: _export,
              ),
            ],
          ),
        ),
        material.Expanded(
          child: material.RepaintBoundary(
            key: _boundaryKey,
            child: material.ColoredBox(
              color: wb.surface,
              child: material.Padding(
                padding: const material.EdgeInsets.all(16),
                child: points.isEmpty
                    ? material.Center(
                        child: Text('No data',
                            style:
                                material.TextStyle(color: wb.mutedForeground)))
                    : _buildChart(context, points),
              ),
            ),
          ),
        ),
      ],
    );
  }

  material.Widget _buildChart(
      material.BuildContext context, List<ChartPoint> points) {
    final palette = context.semanticPalette;
    final wb = context.workbench;
    final label = material.TextStyle(color: wb.mutedForeground, fontSize: 10);
    final colors = [
      palette.type1,
      palette.type2,
      palette.type3,
      palette.type4,
      palette.type5,
    ];
    final step = (points.length / 8).ceil().clamp(1, 1000);

    material.Widget bottom(double v, TitleMeta meta) {
      final i = v.toInt();
      if (i < 0 || i >= points.length || i % step != 0) {
        return const material.SizedBox.shrink();
      }
      return SideTitleWidget(
        meta: meta,
        child: Text(points[i].label, style: label, maxLines: 1),
      );
    }

    final titles = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
            showTitles: true, reservedSize: 28, getTitlesWidget: bottom),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 48,
          getTitlesWidget: (v, meta) => SideTitleWidget(
              meta: meta, child: Text(meta.formattedValue, style: label)),
        ),
      ),
    );
    final grid = FlGridData(
      getDrawingHorizontalLine: (_) =>
          FlLine(color: wb.borderSubtle, strokeWidth: 1),
      drawVerticalLine: false,
    );

    switch (_type) {
      case QuickChartType.bar:
        return BarChart(BarChartData(
          titlesData: titles,
          gridData: grid,
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                  '${points[group.x].label}\n${rod.toY}', const TextStyle()),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: points[i].value, color: palette.type1),
              ]),
          ],
        ));
      case QuickChartType.line:
        return LineChart(LineChartData(
          titlesData: titles,
          gridData: grid,
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                      '${points[s.x.toInt()].label}\n${s.y}', const TextStyle()),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i].value),
              ],
              color: palette.type1,
              barWidth: 2,
              dotData: FlDotData(show: points.length <= 50),
            ),
          ],
        ));
      case QuickChartType.pie:
        return PieChart(PieChartData(
          sectionsSpace: 1,
          sections: [
            for (var i = 0; i < points.length; i++)
              PieChartSectionData(
                value: points[i].value,
                color: colors[i % colors.length],
                radius: 100,
                title: points.length <= 8 ? points[i].label : '',
                titleStyle: const TextStyle(fontSize: 11),
              ),
          ],
        ));
    }
  }
}
