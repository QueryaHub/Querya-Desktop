import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/grid_selection_calc_engine.dart';

void main() {
  group('GridSelectionCalcEngine.formatNum (#1531)', () {
    test('trims trailing zeros and a dangling dot', () {
      expect(GridSelectionCalcEngine.formatNum(null), '-');
      expect(GridSelectionCalcEngine.formatNum(3.0), '3');
      expect(GridSelectionCalcEngine.formatNum(3.14), '3.14');
      expect(GridSelectionCalcEngine.formatNum(0.5), '0.5');
      expect(GridSelectionCalcEngine.formatNum(-2.5), '-2.5');
      expect(GridSelectionCalcEngine.formatNum(1 / 3), '0.3333');
      expect(GridSelectionCalcEngine.formatNum(0.1 + 0.2), '0.3');
      expect(GridSelectionCalcEngine.formatNum(1234.5678), '1234.5678');
    });

    test('values that round to a whole number keep their integer zeros', () {
      expect(GridSelectionCalcEngine.formatNum(2.5000001), '2.5');
      expect(GridSelectionCalcEngine.formatNum(10.00001), '10');
      expect(GridSelectionCalcEngine.formatNum(100.00004), '100');
      expect(GridSelectionCalcEngine.formatNum(0.00001), '0');
    });
  });

  group('GridSelectionCalcEngine.compute with thousands separators (#1520)', () {
    test('commas are stripped only for parsing, distinct keeps the text', () {
      final stats = GridSelectionCalcEngine.compute(
        ['1,000', ' 2,500.5 ', 'NULL', '', 'abc', '3', '3'],
      );
      expect(stats.totalCount, 7);
      expect(stats.nullCount, 2);
      expect(stats.distinctCount, 4); // '1,000', '2,500.5', 'abc', '3'
      expect(stats.numericCount, 4);
      expect(stats.sum, 3506.5);
      expect(stats.min, 3);
      expect(stats.max, 2500.5);
      expect(stats.median, closeTo(501.5, 1e-9)); // (3 + 1000) / 2
    });
  });

  group('GridSelectionCalcEngine.parseThousandsSeparated (#1520)', () {
    // What it replaces: drop every comma, then double.tryParse.
    double? copy(String s) => double.tryParse(s.replaceAll(',', ''));

    test('reads the same numbers as dropping the commas', () {
      for (final s in [
        '1,000',
        '2,500.5',
        '-1,234.56',
        '+3,000',
        '0,0',
        '0.001,5',
        '1,0e-3',
        '1e,6',
        ',-327',
        '5,.',
        ',.5',
        '12,345,678,901,234,567,890',
        '9,007,199,254,740,993',
        '1,e22',
        '1,e23',
        '1,e-400',
        '1,e400',
      ]) {
        final expected = copy(s);
        final actual = GridSelectionCalcEngine.parseThousandsSeparated(s);
        expect(actual, expected, reason: s);
      }
    });

    test('-0 keeps its sign', () {
      expect(
        GridSelectionCalcEngine.parseThousandsSeparated('-0,0')!.isNegative,
        isTrue,
      );
    });

    test('text with commas is not a number', () {
      for (final s in ['Doe, John', ',', '1,,e', '1, 000', '1.2,3.4', 'e,5']) {
        expect(
          GridSelectionCalcEngine.parseThousandsSeparated(s),
          copy(s),
          reason: s,
        );
      }
    });
  });
}
