import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/grid_filter_engine.dart';

void main() {
  group('GridFilterEngine Quoted Literals and Column Identifiers (#903)', () {
    final columns = ['id', 'First Name', 'status', 'category', 'unit_price', 'notes'];
    final rows = [
      ['1', 'John Doe', 'IN PROGRESS', 'Electronics & Gadgets', '99.99', 'NULL'],
      ['2', 'Jane Smith', 'COMPLETED', 'Books & Literature', '15.50', 'Needs review'],
      ['3', "Alice O'Connor", 'IN PROGRESS', 'Home & Kitchen', '8.00', 'Special order'],
      ['4', 'Bob "The Builder"', 'PENDING REVIEW', 'Tools & Hardware', '120.00', ''],
      ['5', 'Charlie Brown', 'WAITING FOR APPROVAL', 'Toys & Games', '25.00', 'NULL'],
    ];

    test('filters by predicate comparing against single-quoted string containing spaces', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: "status = 'IN PROGRESS'",
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 2]));
    });

    test('filters by predicate comparing against double-quoted string containing spaces and ampersand', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: 'category = "Electronics & Gadgets"',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0]));
    });

    test('filters with predicate without spaces around operator (col="val with spaces")', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: 'status="IN PROGRESS"',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 2]));
    });

    test('filters with double-quoted column identifier containing spaces', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: '"First Name" = \'Jane Smith\'',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([1]));
    });

    test('filters with backtick-quoted column identifier', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: '`unit_price` > 50',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 3]));
    });

    test('filters with backtick-quoted column identifier and comparison against decimal string', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: '`unit_price` = 15.50',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([1]));
    });

    test('filters with LIKE pattern containing spaces', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: "status LIKE '%IN PROGRESS%'",
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 2]));
    });

    test('filters with ILIKE pattern containing spaces and case-insensitivity', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: '"First Name" ILIKE \'%jane smith%\'',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([1]));
    });

    test('filters with NOT LIKE pattern containing spaces', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: "status NOT LIKE '%IN PROGRESS%'",
        columns: columns,
        rows: rows,
      );
      expect(res, equals([1, 3, 4]));
    });

    test('filters with IN list containing strings with spaces', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: "status IN ('IN PROGRESS', 'PENDING REVIEW')",
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 2, 3]));
    });

    test('filters with quoted column identifier and IS NULL / IS NOT NULL', () {
      final resNull = GridFilterEngine.filterRowIndices(
        filterText: 'notes IS NULL',
        columns: columns,
        rows: rows,
      );
      expect(resNull, equals([0, 3, 4]));

      final resNotNull = GridFilterEngine.filterRowIndices(
        filterText: '`notes` IS NOT NULL',
        columns: columns,
        rows: rows,
      );
      expect(resNotNull, equals([1, 2]));
    });

    test('handles single quote escapes (both doubled \'\' and backslash \\\')', () {
      final resDoubled = GridFilterEngine.filterRowIndices(
        filterText: '"First Name" = \'Alice O\'\'Connor\'',
        columns: columns,
        rows: rows,
      );
      expect(resDoubled, equals([2]));

      final resBackslash = GridFilterEngine.filterRowIndices(
        filterText: '"First Name" = \'Alice O\\\'Connor\'',
        columns: columns,
        rows: rows,
      );
      expect(resBackslash, equals([2]));
    });

    test('handles double quote escapes (both doubled "" and backslash \\")', () {
      final resBackslash = GridFilterEngine.filterRowIndices(
        filterText: '"First Name" = "Bob \\"The Builder\\""',
        columns: columns,
        rows: rows,
      );
      expect(resBackslash, equals([3]));

      final resDoubled = GridFilterEngine.filterRowIndices(
        filterText: '"First Name" = "Bob ""The Builder"""',
        columns: columns,
        rows: rows,
      );
      expect(resDoubled, equals([3]));
    });

    test('filters with BETWEEN range containing spaced strings or numbers', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: '`unit_price` BETWEEN 10 AND 100',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 1, 4]));
    });

    test('filters with combined complex boolean expression with quoted columns and values', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: '("First Name" = \'John Doe\' OR status = \'WAITING FOR APPROVAL\') AND `unit_price` > 20',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0, 4]));
    });

    test('filters by free text search with quoted multi-word phrase', () {
      final res = GridFilterEngine.filterRowIndices(
        filterText: '"John Doe"',
        columns: columns,
        rows: rows,
      );
      expect(res, equals([0]));
    });
  });
}
