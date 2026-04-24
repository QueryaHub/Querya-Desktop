import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_utils.dart';

void main() {
  group('quotePostgresIdentifier', () {
    test('quotes simple identifier', () {
      expect(quotePostgresIdentifier('users'), '"users"');
      expect(quotePostgresIdentifier('public'), '"public"');
    });

    test('doubles internal double-quotes', () {
      expect(quotePostgresIdentifier('say "hello"'), '"say ""hello"""');
      expect(quotePostgresIdentifier('a""b'), '"a""""b"');
    });

    test('handles empty string', () {
      expect(quotePostgresIdentifier(''), '""');
    });

    test('handles mixed case and special chars', () {
      expect(quotePostgresIdentifier('MyTable'), '"MyTable"');
      expect(quotePostgresIdentifier('schema.name'), '"schema.name"');
    });
  });

  group('postgresBrowseSelectSql', () {
    test('quotes identifiers and uses default limit', () {
      expect(
        postgresBrowseSelectSql(schema: 'public', table: 'stock'),
        'SELECT * FROM "public"."stock" LIMIT 200 OFFSET 0;\n',
      );
    });
  });

  group('convertResultRowsToStrings', () {
    test('converts null to "NULL"', () {
      final result = convertResultRowsToStrings([
        [null, 1],
        [2, null],
      ]);
      expect(result, [
        ['NULL', '1'],
        ['2', 'NULL'],
      ]);
    });

    test('converts int and string', () {
      final result = convertResultRowsToStrings([
        [42, 'hello'],
        [0, ''],
      ]);
      expect(result, [
        ['42', 'hello'],
        ['0', ''],
      ]);
    });

    test('converts DateTime to ISO8601', () {
      final dt = DateTime.utc(2026, 3, 15, 12, 30, 45);
      final result = convertResultRowsToStrings([
        [dt],
      ]);
      expect(result, [
        [dt.toIso8601String()],
      ]);
    });

    test('converts double and bool', () {
      final result = convertResultRowsToStrings([
        [3.14, true],
        [0.0, false],
      ]);
      expect(result, [
        ['3.14', 'true'],
        ['0.0', 'false'],
      ]);
    });

    test('empty list returns empty list', () {
      expect(convertResultRowsToStrings([]), []);
    });

    test('empty row returns list of empty strings for nulls', () {
      final result = convertResultRowsToStrings([
        [null, null],
      ]);
      expect(result, [
        ['NULL', 'NULL'],
      ]);
    });

    test('single row with mixed types', () {
      final result = convertResultRowsToStrings([
        [1, null, 'x', 2.5, true, DateTime.utc(2026, 1, 1)],
      ]);
      expect(result.length, 1);
      expect(result.first, ['1', 'NULL', 'x', '2.5', 'true', '2026-01-01T00:00:00.000Z']);
    });
  });
}
