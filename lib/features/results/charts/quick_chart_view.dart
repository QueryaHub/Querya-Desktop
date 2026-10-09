import 'dart:convert' show utf8;
import 'dart:math' show min, pi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/results/charts/chart_data.dart';
import 'package:querya_desktop/features/results/charts/chart_format.dart';
import 'package:querya_desktop/features/results/charts/chart_svg.dart';
import 'package:querya_desktop/shared/widgets/querya_badge.dart';
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

/// Saves rendered chart SVG text; replaceable in tests.
typedef ChartSvgSaver = Future<void> Function(String svg);

Future<void> _defaultSvgSaver(String svg) async {
  final location = await getSaveLocation(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'SVG', extensions: ['svg']),
    ],
    suggestedName: 'chart.svg',
  );
  if (location == null) return;
  await XFile.fromData(Uint8List.fromList(utf8.encode(svg)),
          mimeType: 'image/svg+xml', name: 'chart.svg')
      .saveTo(location.path);
}

/// 1-click chart tab: pick X / Y columns and a chart type, export as PNG.
class QuickChartView extends material.StatefulWidget {
  const QuickChartView({
    super.key,
    required this.columns,
    required this.rows,
    this.onSavePng,
    this.onSaveSvg,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final ChartPngSaver? onSavePng;
  final ChartSvgSaver? onSaveSvg;

  @override
  material.State<QuickChartView> createState() => _QuickChartViewState();
}

class _QuickChartViewState extends material.State<QuickChartView> {
  final _boundaryKey = material.GlobalKey();
  QuickChartType _type = QuickChartType.bar;
  int? _labelCol;
  int? _valueCol;
  List<int> _numeric = const [];
  ChartAggregation _aggregation = ChartAggregation.none;
  int? _topN = ChartData.defaultTopN;
  int? _hoveredSlice;

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
    _aggregation = _defaultAggregation(_valueCol!);
  }

  ChartAggregation _defaultAggregation(int valueCol) =>
      ChartData.defaultAggregation(
        rows: widget.rows,
        labelColumn: _labelCol,
        valueColumn: valueCol,
      );

  /// What the X control means: a time axis for lines, categories otherwise.
  String get _xLabel => _type == QuickChartType.line ? 'Time' : 'Category';

  String get _xName => _labelCol == null ? '(row #)' : widget.columns[_labelCol!];

  String get _yName => widget.columns[_valueCol!];

  /// "`Y` by `X`", plus the aggregation when one is applied. Used on screen,
  /// in the PNG and in the SVG.
  String _chartTitle() {
    final agg = _type == QuickChartType.line ? ChartAggregation.none : _aggregation;
    final base = '$_yName by $_xName';
    return agg == ChartAggregation.none
        ? base
        : '$base (${_aggregationLabel(agg)})';
  }

  static String _aggregationLabel(ChartAggregation a) => switch (a) {
        ChartAggregation.none => 'None',
        ChartAggregation.sum => 'Sum',
        ChartAggregation.count => 'Count',
        ChartAggregation.avg => 'Avg',
        ChartAggregation.min => 'Min',
        ChartAggregation.max => 'Max',
      };

  /// Points for the current X / Y / type. Line charts never aggregate or cut
  /// categories; they report the rows beyond the cap instead.
  ChartSeries _series(int valueCol) {
    final isLine = _type == QuickChartType.line;
    return ChartData.build(
      rows: widget.rows,
      labelColumn: _labelCol,
      valueColumn: valueCol,
      type: _type,
      aggregation: isLine ? ChartAggregation.none : _aggregation,
      topN: isLine ? null : _topN,
    );
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

  Future<void> _exportSvg() async {
    final valueCol = _valueCol;
    if (valueCol == null) return;
    final palette = context.semanticPalette;
    final wb = context.workbench;
    final svg = ChartSvg.build(
      points: _series(valueCol).points,
      type: _type,
      title: _chartTitle(),
      colors: ChartSvgColors(
        background: ChartSvgColors.hex(wb.surface.toARGB32()),
        text: ChartSvgColors.hex(wb.mutedForeground.toARGB32()),
        grid: ChartSvgColors.hex(wb.borderSubtle.toARGB32()),
        series: [
          for (final c in [
            palette.type1,
            palette.type2,
            palette.type3,
            palette.type4,
            palette.type5,
          ])
            ChartSvgColors.hex(c.toARGB32()),
        ],
      ),
    );
    await (widget.onSaveSvg ?? _defaultSvgSaver)(svg);
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
    final series = _series(_valueCol!);
    final points = series.points;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Padding(
          padding: const material.EdgeInsets.all(8),
          // Wrap, not Row: on a narrow chart the controls move to a second
          // line instead of overflowing and pushing the export buttons away.
          child: material.Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: material.WrapCrossAlignment.center,
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
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  _topN = _type == QuickChartType.pie
                      ? ChartData.pieTopN
                      : ChartData.defaultTopN;
                  _hoveredSlice = null;
                }),
              ),
              const material.SizedBox(width: 12),
              Text(_xLabel),
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
                onSelected: (v) => setState(() {
                  _labelCol = (v == null || v < 0) ? null : v;
                  _aggregation = _defaultAggregation(_valueCol!);
                }),
              ),
              const material.SizedBox(width: 12),
              const Text('Value'),
              const material.SizedBox(width: 6),
              QueryaDropdown<int>(
                key: const material.ValueKey('chart_y'),
                value: _valueCol!,
                width: 160,
                items: [
                  for (final i in _numeric)
                    QueryaDropdownItem(value: i, label: widget.columns[i]),
                ],
                onSelected: (v) => setState(() {
                  _valueCol = v ?? _valueCol;
                  _aggregation = _defaultAggregation(_valueCol!);
                }),
              ),
              if (_type != QuickChartType.line) ...[
                const material.SizedBox(width: 12),
                const Text('Agg'),
                const material.SizedBox(width: 6),
                QueryaDropdown<ChartAggregation>(
                  key: const material.ValueKey('chart_aggregation'),
                  value: _aggregation,
                  width: 110,
                  items: [
                    for (final a in ChartAggregation.values)
                      QueryaDropdownItem(
                          value: a, label: _aggregationLabel(a)),
                  ],
                  onSelected: (v) =>
                      setState(() => _aggregation = v ?? _aggregation),
                ),
                const material.SizedBox(width: 12),
                const Text('Top'),
                const material.SizedBox(width: 6),
                QueryaDropdown<int>(
                  key: const material.ValueKey('chart_top_n'),
                  value: _topN ?? 0,
                  width: 90,
                  items: [
                    for (final n in ChartData.topNChoices)
                      QueryaDropdownItem(
                          value: n ?? 0, label: n == null ? 'All' : '$n'),
                  ],
                  onSelected: (v) =>
                      setState(() => _topN = (v == null || v == 0) ? null : v),
                ),
              ],
              if (series.droppedRows > 0) ...[
                QueryaBadge.status(
                  '${points.length} of ${points.length + series.droppedRows} rows',
                  status: QueryaBadgeStatus.warning,
                ),
                const material.SizedBox(width: 8),
              ],
              material.IconButton(
                key: const material.ValueKey('chart_export'),
                tooltip: 'Export PNG',
                icon: const material.Icon(material.Icons.image_outlined),
                onPressed: _export,
              ),
              material.IconButton(
                key: const material.ValueKey('chart_export_svg'),
                tooltip: 'Export SVG',
                icon: const material.Icon(material.Icons.polyline_outlined),
                onPressed: _exportSvg,
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
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    material.Text(_chartTitle(),
                        maxLines: 1,
                        overflow: material.TextOverflow.ellipsis,
                        style: material.TextStyle(
                            fontSize: 13,
                            fontWeight: material.FontWeight.w600,
                            color: wb.mutedForeground)),
                    const material.SizedBox(height: 8),
                    material.Expanded(
                      child: points.isEmpty
                          ? material.Center(
                              child: Text('No data',
                                  style: material.TextStyle(
                                      color: wb.mutedForeground)))
                          : _buildChart(context, points),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Donut sized to the pane, with a legend beside it (wide) or below it.
  /// Hovering a slice or its legend row highlights both.
  material.Widget _buildPie(
      material.BuildContext context, List<ChartPoint> points) {
    final palette = context.semanticPalette;
    final wb = context.workbench;
    final base = [
      palette.type1,
      palette.type2,
      palette.type3,
      palette.type4,
      palette.type5,
    ];
    final total = points.fold<double>(0, (s, p) => s + p.value);

    // Five palette colours; each further round is tinted towards the muted
    // text colour, so slices stay distinct up to 25 of them.
    material.Color colorOf(int i) {
      final round = i ~/ base.length;
      final c = base[i % base.length];
      return round == 0
          ? c
          : material.Color.lerp(c, wb.mutedForeground, 0.35 * round)!;
    }

    material.Color contrastOn(material.Color c) =>
        c.computeLuminance() > 0.5 ? material.Colors.black : material.Colors.white;

    material.Widget legendRow(int i) {
      final p = points[i];
      final share = total > 0 ? p.value / total * 100 : 0.0;
      final hovered = _hoveredSlice == i;
      final valueText = p.value == p.value.roundToDouble()
          ? p.value.toInt().toString()
          : p.value.toStringAsFixed(2);
      return material.MouseRegion(
        onEnter: (_) => setState(() => _hoveredSlice = i),
        onExit: (_) => setState(() => _hoveredSlice = null),
        child: material.Container(
          color: hovered ? wb.accent.withValues(alpha: 0.12) : null,
          padding: const material.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: material.Row(
            children: [
              material.Container(
                  width: 10, height: 10, color: colorOf(i)),
              const material.SizedBox(width: 6),
              material.Expanded(
                child: material.Text(p.label,
                    maxLines: 1,
                    overflow: material.TextOverflow.ellipsis,
                    style: const material.TextStyle(fontSize: 12)),
              ),
              const material.SizedBox(width: 8),
              material.Text(valueText,
                  style: material.TextStyle(
                      fontSize: 11, color: wb.mutedForeground)),
              const material.SizedBox(width: 8),
              material.SizedBox(
                width: 48,
                child: material.Text('${share.toStringAsFixed(1)}%',
                    textAlign: material.TextAlign.right,
                    style: const material.TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
      );
    }

    final legend = material.ListView(
      padding: material.EdgeInsets.zero,
      children: [for (var i = 0; i < points.length; i++) legendRow(i)],
    );

    return material.LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 520;
      final chart = material.Expanded(
        child: material.LayoutBuilder(builder: (context, c) {
          final side = min(c.maxWidth, c.maxHeight);
          // Leaves room for the touched slice to grow.
          final outer = side / 2 * 0.88;
          final hole = outer * 0.45;
          return material.Center(
            child: material.SizedBox(
              width: side,
              height: side,
              child: PieChart(PieChartData(
                sectionsSpace: 1,
                centerSpaceRadius: hole,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    final i = response?.touchedSection?.touchedSectionIndex;
                    if (_hoveredSlice != i) setState(() => _hoveredSlice = i);
                  },
                ),
                sections: [
                  for (var i = 0; i < points.length; i++)
                    PieChartSectionData(
                      value: points[i].value,
                      color: colorOf(i),
                      radius: outer - hole + (_hoveredSlice == i ? 8 : 0),
                      title: total > 0 && points[i].value / total >= 0.05
                          ? '${(points[i].value / total * 100).round()}%'
                          : '',
                      titleStyle: TextStyle(
                          fontSize: 11, color: contrastOn(colorOf(i))),
                    ),
                ],
              )),
            ),
          );
        }),
      );

      if (wide) {
        return material.Row(children: [
          chart,
          const material.SizedBox(width: 12),
          material.SizedBox(width: 240, child: legend),
        ]);
      }
      return material.Column(children: [
        chart,
        material.SizedBox(height: 150, child: legend),
      ]);
    });
  }

  material.Widget _buildChart(
      material.BuildContext context, List<ChartPoint> points) {
    if (_type == QuickChartType.pie) return _buildPie(context, points);
    return material.LayoutBuilder(
        builder: (context, box) => _axisChart(context, points, box.maxWidth));
  }

  /// Bar and line charts. [width] decides whether X labels fit or rotate.
  material.Widget _axisChart(
      material.BuildContext context, List<ChartPoint> points, double width) {
    final palette = context.semanticPalette;
    final wb = context.workbench;
    final cs = Theme.of(context).colorScheme;
    final label = material.TextStyle(color: wb.mutedForeground, fontSize: 10);
    final step = (points.length / 8).ceil().clamp(1, 1000);
    // Labels shown: one per step. Rotate them when a slot is too narrow.
    final shown = (points.length / step).ceil().clamp(1, 1000);
    final slot = (width - 60) / shown;
    final rotate = slot < 60;

    material.Widget bottom(double v, TitleMeta meta) {
      final i = v.toInt();
      if (i < 0 || i >= points.length || i % step != 0) {
        return const material.SizedBox.shrink();
      }
      final text = material.Text(
        points[i].label,
        style: label,
        maxLines: 1,
        overflow: material.TextOverflow.ellipsis,
      );
      return SideTitleWidget(
        meta: meta,
        child: rotate
            ? material.Transform.rotate(
                angle: -pi / 4,
                alignment: material.Alignment.topRight,
                child: material.ConstrainedBox(
                  constraints:
                      const material.BoxConstraints(maxWidth: 120),
                  child: text,
                ),
              )
            : material.ConstrainedBox(
                constraints: material.BoxConstraints(maxWidth: slot),
                child: text,
              ),
      );
    }

    final axisLabel = material.TextStyle(color: wb.mutedForeground, fontSize: 11);
    final titles = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      bottomTitles: AxisTitles(
        axisNameSize: 18,
        axisNameWidget: material.Text(_xName, style: axisLabel),
        sideTitles: SideTitles(
            showTitles: true,
            reservedSize: rotate ? 52 : 28,
            getTitlesWidget: bottom),
      ),
      leftTitles: AxisTitles(
        axisNameSize: 18,
        axisNameWidget: material.Text(_yName, style: axisLabel),
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 52,
          getTitlesWidget: (v, meta) => SideTitleWidget(
              meta: meta,
              child: material.Text(ChartFormat.compact(v), style: label)),
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
              getTooltipColor: (_) => cs.popover,
              tooltipBorder: material.BorderSide(color: cs.border),
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                  '${points[group.x].label}\n${ChartFormat.full(rod.toY)}',
                  material.TextStyle(
                      color: cs.popoverForeground, fontSize: 12)),
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
              getTooltipColor: (_) => cs.popover,
              tooltipBorder: material.BorderSide(color: cs.border),
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                      '${points[s.x.toInt()].label}\n${ChartFormat.full(s.y)}',
                      material.TextStyle(
                          color: cs.popoverForeground, fontSize: 12)),
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
        return _buildPie(context, points);
    }
  }
}
