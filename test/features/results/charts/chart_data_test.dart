import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/results/charts/chart_data.dart';

void main() {
  group('ChartData.parseNumber', () {
    test('parses numbers and rejects junk', () {
      expect(ChartData.parseNumber(' 12.5 '), 12.5);
      expect(ChartData.parseNumber('-3'), -3);
      expect(ChartData.parseNumber(''), isNull);
      expect(ChartData.parseNumber('abc'), isNull);
      expect(ChartData.parseNumber('NaN'), isNull);
      expect(ChartData.parseNumber('Infinity'), isNull);
    });
  });

  group('ChartData.numericColumns', () {
    test('detects numeric columns ignoring empty cells', () {
      final cols = ['id', 'name', 'amount', 'empty'];
      final rows = [
        ['1', 'a', '1.5', ''],
        ['2', 'b', '', ''],
        ['3', 'c', '4', ''],
      ];
      expect(ChartData.numericColumns(cols, rows), [0, 2]);
    });

    test('mixed column is not numeric', () {
      expect(
        ChartData.numericColumns(['x'], [
          ['1'],
          ['oops'],
        ]),
        isEmpty,
      );
    });
  });

  group('ChartData.build', () {
    final rows = [
      ['a', '1'],
      ['b', 'x'],
      ['a', '3'],
      ['c', '-2'],
    ];

    test('bar skips non numeric rows and keeps order', () {
      final pts = ChartData.build(
        rows: rows,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.bar,
      );
      expect(pts.map((p) => p.label), ['a', 'a', 'c']);
      expect(pts.map((p) => p.value), [1, 3, -2]);
    });

    test('uses row number when no label column', () {
      final pts = ChartData.build(
        rows: rows,
        labelColumn: null,
        valueColumn: 1,
        type: QuickChartType.line,
      );
      expect(pts.first.label, '1');
      expect(pts.last.label, '4');
    });

    test('pie aggregates labels and drops non-positive values', () {
      final pts = ChartData.build(
        rows: rows,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.pie,
      );
      expect(pts.length, 1);
      expect(pts.single.label, 'a');
      expect(pts.single.value, 4);
    });

    test('bar truncates and pie folds tail into Other', () {
      final many = [
        for (var i = 0; i < 80; i++) ['k$i', '${i + 1}'],
      ];
      final bar = ChartData.build(
        rows: many,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.bar,
      );
      expect(bar.length, ChartData.maxPoints);
      final pie = ChartData.build(
        rows: many,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.pie,
      );
      expect(pie.length, ChartData.maxPoints);
      expect(pie.last.label, 'Other');
    });
  });
}
