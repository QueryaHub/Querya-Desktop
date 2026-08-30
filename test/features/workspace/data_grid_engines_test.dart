import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/grid_filter_engine.dart';
import 'package:querya_desktop/features/workspace/grid_groupings_engine.dart';
import 'package:querya_desktop/features/workspace/grid_selection_calc_engine.dart';

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

    test('filters with LIKE and ILIKE wildcards', () {
      final resLike = GridFilterEngine.filterRowIndices(
        filterText: "status LIKE 'ACT%'",
        columns: columns,
        rows: rows,
      );
      expect(resLike, equals([0, 2]));

      final resIlike = GridFilterEngine.filterRowIndices(
        filterText: "status ILIKE '%pend%'",
        columns: columns,
        rows: rows,
      );
      expect(resIlike, equals([1]));
    });

    test('filters with IN and NOT IN list of literals', () {
      final resIn = GridFilterEngine.filterRowIndices(
        filterText: "status IN ('PENDING', 'CANCELLED')",
        columns: columns,
        rows: rows,
      );
      expect(resIn, equals([1, 3]));

      final resNotIn = GridFilterEngine.filterRowIndices(
        filterText: "status NOT IN ('ACTIVE')",
        columns: columns,
        rows: rows,
      );
      expect(resNotIn, equals([1, 3]));
    });

    test('filters with IS NULL and IS NOT NULL', () {
      final rowsWithNull = [
        ['1', 'ACTIVE', '100'],
        ['2', 'NULL', '200'],
        ['3', '', '300'],
      ];
      final resNull = GridFilterEngine.filterRowIndices(
        filterText: 'status IS NULL',
        columns: columns,
        rows: rowsWithNull,
      );
      expect(resNull, equals([1, 2]));

      final resNotNull = GridFilterEngine.filterRowIndices(
        filterText: 'status IS NOT NULL',
        columns: columns,
        rows: rowsWithNull,
      );
      expect(resNotNull, equals([0]));
    });

    test('filters with BETWEEN range', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: 'amount BETWEEN 50 AND 200',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 1]));
    });

    test('handles escaped quotes inside string literals', () {
      final rowsWithQuotes = [
        ['1', "O'Connor", '100'],
        ['2', 'Smith', '200'],
      ];
      final res = GridFilterEngine.filterRowIndices(
        filterText: "status = 'O''Connor'",
        columns: columns,
        rows: rowsWithQuotes,
      );
      expect(res, equals([0]));
    });
  });

  group('GridSelectionCalcEngine', () {
    test('computes correct stats for numeric values', () {
      final stats = GridSelectionCalcEngine.compute(['10', '20', '30', '40']);
      expect(stats.totalCount, equals(4));
      expect(stats.distinctCount, equals(4));
      expect(stats.numericCount, equals(4));
      expect(stats.nullCount, equals(0));
      expect(stats.sum, equals(100.0));
      expect(stats.average, equals(25.0));
      expect(stats.median, equals(25.0));
      expect(stats.min, equals(10.0));
      expect(stats.max, equals(40.0));
    });

    test('computes odd-length median and distinct count with duplicates', () {
      final stats = GridSelectionCalcEngine.compute(['10', '20', '20', '50', '100']);
      expect(stats.distinctCount, equals(4));
      expect(stats.median, equals(20.0));
      expect(stats.toSummaryString(), contains('Count: 5 | Distinct: 4'));
      expect(stats.toSummaryString(), contains('Median: 20'));
    });

    test('handles NULLs and mixed string data', () {
      final stats = GridSelectionCalcEngine.compute(['10', 'NULL', 'text', '50.5']);
      expect(stats.totalCount, equals(4));
      expect(stats.distinctCount, equals(3));
      expect(stats.numericCount, equals(2));
      expect(stats.nullCount, equals(1));
      expect(stats.sum, equals(60.5));
      expect(stats.average, equals(30.25));
      expect(stats.min, equals(10.0));
      expect(stats.max, equals(50.5));
    });

    test('computes correct QuickSelect median for large odd and even selections (> 500)', () {
      // Odd length > 500 (1001 items)
      final oddData = List<String>.generate(1001, (i) => '${(i * 3) % 1000}');
      final oddStats = GridSelectionCalcEngine.compute(oddData);
      final oddParsed = oddData.map(double.parse).toList()..sort();
      expect(oddStats.median, equals(oddParsed[500]));

      // Even length > 500 (1000 items)
      final evenData = List<String>.generate(1000, (i) => '${(i * 7) % 2000}');
      final evenStats = GridSelectionCalcEngine.compute(evenData);
      final evenParsed = evenData.map(double.parse).toList()..sort();
      final expectedEvenMedian = (evenParsed[499] + evenParsed[500]) / 2.0;
      expect(evenStats.median, equals(expectedEvenMedian));
    });

    test('computeAdaptive returns empty stats for empty list', () async {
      final stats = await GridSelectionCalcEngine.computeAdaptive(const []);
      expect(stats, equals(GridCalcStats.empty));
    });

    test('computeAdaptive computes synchronously below threshold', () async {
      final values = ['10', '20', '30'];
      final stats = await GridSelectionCalcEngine.computeAdaptive(values, threshold: 10);
      expect(stats.totalCount, 3);
      expect(stats.sum, 60.0);
      expect(stats.average, 20.0);
    });

    test('computeAdaptive computes via background isolate above threshold', () async {
      final values = List<String>.generate(100, (i) => '$i');
      final stats = await GridSelectionCalcEngine.computeAdaptive(values, threshold: 50);
      expect(stats.totalCount, 100);
      expect(stats.min, 0.0);
      expect(stats.max, 99.0);
      expect(stats.sum, 4950.0);
    });
  });

  group('GridGroupingsEngine', () {
    final rows = [
      ['1', 'ACTIVE', '100'],
      ['2', 'PENDING', '50'],
      ['3', 'ACTIVE', '200'],
      ['4', 'ACTIVE', '300'],
      ['5', 'CANCELLED', '0'],
    ];

    test('groups rows by column index and calculates percentages', () {
      final groups = GridGroupingsEngine.buildGroups(
        groupColIndices: [1],
        rows: rows,
      );

      expect(groups.length, equals(3));
      expect(groups[0].groupKey, equals('ACTIVE'));
      expect(groups[0].count, equals(3));
      expect(groups[0].percentage, closeTo(60.0, 0.1));
      expect(groups[1].count, equals(1));
    });

    test('computes custom aggregations (SUM and AVG)', () {
      final sumGroups = GridGroupingsEngine.buildGroups(
        groupColIndices: [1],
        rows: rows,
        aggConfig: const GroupAggregationConfig(
          aggType: GroupingAggType.sum,
          targetColIndex: 2,
        ),
      );

      final activeGroup = sumGroups.firstWhere((g) => g.groupKey == 'ACTIVE');
      expect(activeGroup.aggValue, equals(600.0));

      final avgGroups = GridGroupingsEngine.buildGroups(
        groupColIndices: [1],
        rows: rows,
        aggConfig: const GroupAggregationConfig(
          aggType: GroupingAggType.avg,
          targetColIndex: 2,
        ),
      );

      final activeAvg = avgGroups.firstWhere((g) => g.groupKey == 'ACTIVE');
      expect(activeAvg.aggValue, equals(200.0));
    });

    test('sorts groups by key or aggregate', () {
      final keySorted = GridGroupingsEngine.buildGroups(
        groupColIndices: [1],
        rows: rows,
        sortBy: GroupSortBy.key,
        sortAscending: true,
      );

      expect(keySorted[0].groupKey, equals('ACTIVE'));
      expect(keySorted[1].groupKey, equals('CANCELLED'));
      expect(keySorted[2].groupKey, equals('PENDING'));
    });

    test('exports pivot table to CSV format', () {
      final groups = GridGroupingsEngine.buildGroups(
        groupColIndices: [1],
        rows: rows,
        aggConfig: const GroupAggregationConfig(
          aggType: GroupingAggType.sum,
          targetColIndex: 2,
        ),
      );

      final csv = GridGroupingsEngine.exportPivotToCsv(
        groups: groups,
        groupByColumnName: 'status',
      );

      expect(csv, contains('Group Key,Count,Percentage,Aggregate'));
      expect(csv, contains('"ACTIVE",3,60.00%,600.00'));
    });
  });
}
