import 'dart:typed_data';

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

    test('convertSqliteResultRowsToStrings maps nulls, primitives, and blobs',
        () {
      final rawRows = [
        ['sqlite', null, 42],
        [null, null, null],
        [
          Uint8List.fromList(const [0xff]),
          'x',
          1
        ],
      ];
      final job = SqliteResultConvertJob(rowValues: rawRows);
      final out = convertSqliteResultRowsToStrings(job);

      expect(out.length, 3);
      expect(out[0], ['sqlite', 'NULL', '42']);
      expect(out[1], ['NULL', 'NULL', 'NULL']);
      expect(out[2], ["X'ff'", 'x', '1']);
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

  group('convertPostgresResultRowsToStringsAdaptive (single typed pass)', () {
    // Text OIDs plus a date OID: 1082 = date, 25 = text, 23 = int4.
    const oids = [23, 25, 1082, 25];
    List<List<Object?>> sample(int n) => [
          for (var i = 0; i < n; i++)
            [i, i.isEven ? 'active' : 'custom_$i', DateTime.utc(2026, 3, 1 + i % 20), null],
        ];

    test('matches the typed conversion exactly', () async {
      final job = PostgresResultConvertJob(
        rowValues: sample(1200),
        columnTypeOids: oids,
      );
      expect(
        await convertPostgresResultRowsToStringsAdaptive(job),
        convertPostgresResultRowsToStrings(job),
      );
    });

    test('keeps PG typing: date-only OID renders as a date, NULL as NULL',
        () async {
      final out = await convertPostgresResultRowsToStringsAdaptive(
        PostgresResultConvertJob(rowValues: sample(2), columnTypeOids: oids),
      );
      expect(out[0], ['0', 'active', '2026-03-01', 'NULL']);
      expect(out[1][2], '2026-03-02');
    });

    test('uses column data type names when there is no OID', () async {
      final out = await convertPostgresResultRowsToStringsAdaptive(
        PostgresResultConvertJob(
          rowValues: [
            [DateTime.utc(2026, 3, 1, 10)],
          ],
          columnDataTypes: const ['date'],
        ),
      );
      expect(out.single.single, '2026-03-01');
    });

    test('interns repeated values so they share one string instance', () async {
      final out = await convertPostgresResultRowsToStringsAdaptive(
        PostgresResultConvertJob(
          rowValues: [
            for (var i = 0; i < 5; i++) [i, 'status_${i % 2}_${'x' * 3}'],
          ],
          columnTypeOids: const [23, 25],
        ),
      );
      expect(identical(out[0][1], out[2][1]), isTrue);
      expect(identical(out[1][1], out[3][1]), isTrue);
    });

    test('returns every row when yielding to the event loop', () async {
      final out = await convertPostgresResultRowsToStringsAdaptive(
        PostgresResultConvertJob(rowValues: sample(1000), columnTypeOids: oids),
        yieldEvery: 7,
      );
      expect(out, hasLength(1000));
      expect(out.last[0], '999');
    });

    test('empty input yields empty output', () async {
      expect(
        await convertPostgresResultRowsToStringsAdaptive(
          const PostgresResultConvertJob(rowValues: []),
        ),
        isEmpty,
      );
    });

    test('lets the event loop run while converting a large result', () async {
      var ticks = 0;
      final done = convertPostgresResultRowsToStringsAdaptive(
        PostgresResultConvertJob(rowValues: sample(4000), columnTypeOids: oids),
        yieldEvery: 100,
      );
      // Each yield lets this microtask-scheduled timer fire before the end.
      Future<void>.delayed(Duration.zero, () => ticks++);
      await done;
      expect(ticks, 1, reason: 'a queued task ran while conversion was in flight');
    });
  });
}
