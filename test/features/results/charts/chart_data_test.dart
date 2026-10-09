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
      final series = ChartData.build(
        rows: rows,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.bar,
      );
      expect(series.points.map((p) => p.label), ['a', 'a', 'c']);
      expect(series.points.map((p) => p.value), [1, 3, -2]);
      expect(series.droppedRows, 0);
    });

    test('uses row number when no label column', () {
      final pts = ChartData.build(
        rows: rows,
        labelColumn: null,
        valueColumn: 1,
        type: QuickChartType.line,
      ).points;
      expect(pts.first.label, '1');
      expect(pts.last.label, '4');
    });

    test('pie with sum aggregation drops non-positive values', () {
      final pts = ChartData.build(
        rows: rows,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.pie,
        aggregation: ChartAggregation.sum,
      ).points;
      expect(pts.length, 1);
      expect(pts.single.label, 'a');
      expect(pts.single.value, 4);
    });
  });

  group('ChartData aggregation', () {
    // status repeats: a has 1, 3, 5; b has 2; c has 10.
    final rows = [
      ['a', '1'],
      ['b', '2'],
      ['a', '3'],
      ['c', '10'],
      ['a', '5'],
    ];

    ChartSeries bar(ChartAggregation agg) => ChartData.build(
          rows: rows,
          labelColumn: 0,
          valueColumn: 1,
          type: QuickChartType.bar,
          aggregation: agg,
        );

    test('sum groups equal labels in first-seen order', () {
      final pts = bar(ChartAggregation.sum).points;
      expect(pts.map((p) => p.label), ['a', 'b', 'c']);
      expect(pts.map((p) => p.value), [9, 2, 10]);
    });

    test('count counts rows per label', () {
      expect(bar(ChartAggregation.count).points.map((p) => p.value),
          [3, 1, 1]);
    });

    test('avg divides the sum by the count', () {
      expect(bar(ChartAggregation.avg).points.map((p) => p.value), [3, 2, 10]);
    });

    test('min and max pick the extremes per label', () {
      expect(bar(ChartAggregation.min).points.map((p) => p.value), [1, 2, 10]);
      expect(bar(ChartAggregation.max).points.map((p) => p.value), [5, 2, 10]);
    });

    test('none keeps every row as its own bar', () {
      expect(bar(ChartAggregation.none).points.length, rows.length);
    });

    test('default is sum when labels repeat, none otherwise', () {
      expect(
        ChartData.defaultAggregation(
            rows: rows, labelColumn: 0, valueColumn: 1),
        ChartAggregation.sum,
      );
      final unique = [
        ['a', '1'],
        ['b', '2'],
      ];
      expect(
        ChartData.defaultAggregation(
            rows: unique, labelColumn: 0, valueColumn: 1),
        ChartAggregation.none,
      );
    });

    test('row numbers never count as repeated labels', () {
      expect(
        ChartData.defaultAggregation(
            rows: rows, labelColumn: null, valueColumn: 1),
        ChartAggregation.none,
      );
    });
  });

  group('ChartData Top N', () {
    // Ten categories, value k for category k.
    final rows = [
      for (var k = 1; k <= 12; k++) ['k$k', '$k'],
    ];

    test('bar keeps the top N by value and folds the rest into Other', () {
      final pts = ChartData.build(
        rows: rows,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.bar,
        topN: 10,
      ).points;
      expect(pts.length, 11);
      expect(pts.first.label, 'k12');
      expect(pts[9].label, 'k3');
      expect(pts.last.label, ChartData.otherLabel);
      // k1 + k2 folded.
      expect(pts.last.value, 3);
    });

    test('pie folds the tail into Other the same way', () {
      final pts = ChartData.build(
        rows: rows,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.pie,
        topN: 10,
      ).points;
      expect(pts.last.label, ChartData.otherLabel);
      expect(pts.last.value, 3);
    });

    test('no Other when there are not more categories than N', () {
      final pts = ChartData.build(
        rows: rows,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.bar,
        topN: 20,
      ).points;
      expect(pts.length, 12);
      expect(pts.any((p) => p.label == ChartData.otherLabel), isFalse);
    });

    test('All (null) keeps every category and folds nothing', () {
      final pts = ChartData.build(
        rows: rows,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.bar,
      ).points;
      expect(pts.length, 12);
    });
  });

  group('ChartData line cap', () {
    final many = [
      for (var i = 0; i < 80; i++) ['k$i', '${i + 1}'],
    ];

    test('line keeps the first maxPoints and reports the rest', () {
      final series = ChartData.build(
        rows: many,
        labelColumn: 0,
        valueColumn: 1,
        type: QuickChartType.line,
      );
      expect(series.points.length, ChartData.maxPoints);
      expect(series.points.first.label, 'k0');
      expect(series.droppedRows, 80 - ChartData.maxPoints);
    });
  });
}
