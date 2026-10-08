import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/results/charts/chart_data.dart';
import 'package:querya_desktop/features/results/charts/chart_svg.dart';

void main() {
  const colors = ChartSvgColors(
    background: '#101010',
    text: '#aaaaaa',
    grid: '#333333',
    series: ['#ff0000', '#00ff00'],
  );
  const points = [
    ChartPoint('a', 1),
    ChartPoint('b', 3),
    ChartPoint('c', 2),
  ];

  String build(QuickChartType t, [List<ChartPoint> p = points, String? title]) =>
      ChartSvg.build(points: p, type: t, colors: colors, title: title);

  test('hex drops alpha and pads', () {
    expect(ChartSvgColors.hex(0xFF0A0B0C), '#0a0b0c');
    expect(ChartSvgColors.hex(0xFF000001), '#000001');
  });

  test('bar chart draws one rect per point plus the background', () {
    final svg = build(QuickChartType.bar);
    expect(svg, startsWith('<?xml'));
    expect(svg, contains('xmlns="http://www.w3.org/2000/svg"'));
    expect('<rect '.allMatches(svg).length, 1 + points.length);
    expect(svg, contains('fill="#101010"'));
    expect(svg, contains('fill="#ff0000"'));
    expect(svg, contains('<title>b: 3</title>'));
    expect(svg.trimRight(), endsWith('</svg>'));
  });

  test('line chart draws a polyline and a dot per point', () {
    final svg = build(QuickChartType.line);
    expect(svg, contains('<polyline'));
    expect('<circle '.allMatches(svg).length, points.length);
    expect(svg, isNot(contains('<path')));
  });

  test('pie chart draws a slice per point and a percentage legend', () {
    final svg = build(QuickChartType.pie);
    expect('<path '.allMatches(svg).length, points.length);
    expect(svg, contains('a (16.7%)'));
    expect(svg, contains('b (50.0%)'));
  });

  test('a single slice is a full circle', () {
    final svg = build(QuickChartType.pie, const [ChartPoint('only', 5)]);
    expect(svg, contains('<circle'));
    expect(svg, isNot(contains('<path')));
  });

  test('labels and title are XML-escaped', () {
    final svg = build(
      QuickChartType.bar,
      const [ChartPoint('<a&"b">', 1)],
      'x<y',
    );
    expect(svg, contains('&lt;a&amp;&quot;b&quot;&gt;'));
    expect(svg, contains('<title>x&lt;y</title>'));
    expect(svg, isNot(contains('<a&')));
  });

  test('negative values hang below the zero line', () {
    final svg = build(QuickChartType.bar, const [
      ChartPoint('up', 2),
      ChartPoint('down', -2),
    ]);
    expect(svg, contains('<title>down: -2</title>'));
    expect('<rect '.allMatches(svg).length, 3);
  });

  test('empty data still yields a valid document', () {
    final svg = build(QuickChartType.bar, const []);
    expect('<rect '.allMatches(svg).length, 1);
    expect(svg.trimRight(), endsWith('</svg>'));
  });

  test('all-equal values do not divide by zero', () {
    final svg = build(QuickChartType.line, const [
      ChartPoint('a', 0),
      ChartPoint('b', 0),
    ]);
    expect(svg, isNot(contains('NaN')));
    expect(svg, isNot(contains('Infinity')));
  });
}
