import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/grid_filter_engine.dart';
import 'package:querya_desktop/features/main_screen/grid_groupings_engine.dart';
import 'package:querya_desktop/features/main_screen/grid_selection_calc_engine.dart';

void main() {
  group('GridFilterEngine', () {
    final columns = ['id', 'status', 'amount'];
    final rows = [
      ['1', 'ACTIVE', '150.0'],
      ['2', 'PENDING', '50.0'],
      ['3', 'ACTIVE', '300.0'],
      ['4', 'CANCELLED', '0.0'],
    ];

    test('returns all rows when filter is empty', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: '',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 1, 2, 3]));
    });

    test('filters by free text substring search', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: 'active',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 2]));
    });

    test('filters by predicate column = value', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: 'status = PENDING',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([1]));
    });

    test('filters by numeric predicate amount > 100', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: 'amount > 100',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 2]));
    });

    test('filters with AND conjunction', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: "status = 'ACTIVE' AND amount > 200",
        columns: columns,
        rows: rows,
      );
      expect(res, equals([2]));
    });

    test('filters with OR disjunction', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: "status = 'PENDING' OR status = 'CANCELLED'",
        columns: columns,
        rows: rows,
      );
      expect(res, equals([1, 3]));
    });

    test('filters with NOT negation and parentheses', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: "NOT (status = 'ACTIVE') AND amount >= 50",
        columns: columns,
        rows: rows,
      );
      expect(res, equals([1]));
    });

    test('handles combined complex nested logic', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: "(status = 'ACTIVE' OR status = 'PENDING') AND (amount < 200)",
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 1]));
    });
  });

  group('GridSelectionCalcEngine', () {
    test('computes correct stats for numeric values', () {
      final stats = GridSelectionCalcEngine.compute(['10', '20', '30', '40']);
      expect(stats.totalCount, equals(4));
      expect(stats.numericCount, equals(4));
      expect(stats.nullCount, equals(0));
      expect(stats.sum, equals(100.0));
      expect(stats.average, equals(25.0));
      expect(stats.min, equals(10.0));
      expect(stats.max, equals(40.0));
    });

    test('handles NULLs and mixed string data', () {
      final stats = GridSelectionCalcEngine.compute(['10', 'NULL', 'text', '50.5']);
      expect(stats.totalCount, equals(4));
      expect(stats.numericCount, equals(2));
      expect(stats.nullCount, equals(1));
      expect(stats.sum, equals(60.5));
      expect(stats.average, equals(30.25));
      expect(stats.min, equals(10.0));
      expect(stats.max, equals(50.5));
    });
  });

  group('GridGroupingsEngine', () {
    final rows = [
      ['1', 'ACTIVE'],
      ['2', 'PENDING'],
      ['3', 'ACTIVE'],
      ['4', 'ACTIVE'],
      ['5', 'CANCELLED'],
    ];

    test('groups rows by column index and calculates percentages', () {
      final groups = GridGroupingsEngine.buildGroups(
        colIndex: 1,
        rows: rows,
      );

      expect(groups.length, equals(3));
      expect(groups[0].groupKey, equals('ACTIVE'));
      expect(groups[0].count, equals(3));
      expect(groups[0].percentage, closeTo(60.0, 0.1));

      expect(groups[1].count, equals(1));
    });
  });
}
