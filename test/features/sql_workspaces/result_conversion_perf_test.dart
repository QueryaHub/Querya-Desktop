import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mysql/mysql_result_utils.dart';
import 'package:querya_desktop/features/postgresql/postgres_result_utils.dart';
import 'package:querya_desktop/features/sqlite/sqlite_result_utils.dart';

void main() {
  group('Result Conversion Job & Utilities', () {
    test('convertMysqlResultRowsToStrings maps nulls and primitives correctly', () {
      final rawRows = [
        [1, 'hello', null, 3.14, true],
        [2, 'world', 'abc', null, false],
      ];
      final job = MysqlResultConvertJob(rowValues: rawRows);
      final out = convertMysqlResultRowsToStrings(job);

      expect(out.length, 2);
      expect(out[0], ['1', 'hello', 'NULL', '3.14', 'true']);
      expect(out[1], ['2', 'world', 'abc', 'NULL', 'false']);
    });

    test('convertPostgresResultRowsToStrings maps nulls and primitives correctly', () {
      final rawRows = [
        [100, null, 'pg_test'],
        [null, 999, 'foo'],
      ];
      final job = PostgresResultConvertJob(rowValues: rawRows);
      final out = convertPostgresResultRowsToStrings(job);

      expect(out.length, 2);
      expect(out[0], ['100', 'NULL', 'pg_test']);
      expect(out[1], ['NULL', '999', 'foo']);
    });

    test('convertSqliteResultRowsToStrings maps nulls and primitives correctly', () {
      final rawRows = [
        ['sqlite', null, 42],
        [null, null, null],
      ];
      final job = SqliteResultConvertJob(rowValues: rawRows);
      final out = convertSqliteResultRowsToStrings(job);

      expect(out.length, 2);
      expect(out[0], ['sqlite', 'NULL', '42']);
      expect(out[1], ['NULL', 'NULL', 'NULL']);
    });

    test('All convert jobs handle large batches efficiently', () {
      final rawBatch = List.generate(
        2000,
        (r) => List.generate(15, (c) => c % 3 == 0 ? null : 'row_${r}_col_$c'),
      );

      final pgJob = PostgresResultConvertJob(rowValues: rawBatch);
      final pgOut = convertPostgresResultRowsToStrings(pgJob);
      expect(pgOut.length, 2000);
      expect(pgOut.first[0], 'NULL');
      expect(pgOut.first[1], 'row_0_col_1');

      final sqliteJob = SqliteResultConvertJob(rowValues: rawBatch);
      final sqliteOut = convertSqliteResultRowsToStrings(sqliteJob);
      expect(sqliteOut.length, 2000);
      expect(sqliteOut[100][0], 'NULL');
      expect(sqliteOut[100][1], 'row_100_col_1');
    });
  });
}
