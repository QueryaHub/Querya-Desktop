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
}
