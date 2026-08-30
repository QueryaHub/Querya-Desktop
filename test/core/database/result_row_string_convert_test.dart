import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';

void main() {
  group('StringInternPool', () {
    test('deduplicates identical string instances', () {
      final pool = StringInternPool();

      // Create separate String instances dynamically
      final s1 = String.fromCharCodes('active'.codeUnits);
      final s2 = String.fromCharCodes('active'.codeUnits);

      expect(identical(s1, s2), isFalse);

      final interned1 = pool.intern(s1);
      final interned2 = pool.intern(s2);

      expect(identical(interned1, interned2), isTrue);
    });

    test('preloads common database literals', () {
      final pool = StringInternPool();

      expect(identical(pool.internObject(null), 'NULL'), isTrue);
      expect(identical(pool.internObject(true), 'true'), isTrue);
      expect(identical(pool.internObject(false), 'false'), isTrue);
      expect(identical(pool.internObject(0), '0'), isTrue);
      expect(identical(pool.internObject(1), '1'), isTrue);
    });

    test('respects maxStringLength boundary', () {
      final pool = StringInternPool(maxStringLength: 10);
      const longStr = 'this_is_a_very_long_string_that_should_not_be_interned';

      final res = pool.intern(longStr);
      expect(res, longStr);
      // Pool size should not increase for long string
      final initialSize = pool.size;
      pool.intern(longStr);
      expect(pool.size, initialSize);
    });

    test('respects maxEntries capacity limit', () {
      final pool = StringInternPool(maxEntries: 30);

      for (var i = 0; i < 50; i++) {
        pool.intern('unique_key_$i');
      }

      expect(pool.size, lessThanOrEqualTo(30));
    });
  });

  group('result_row_string_convert', () {
    final sampleRows = <List<Object?>>[
      [1, null, 'a'],
      [2, 'x', null],
    ];

    final expectedOutput = [
      ['1', 'NULL', 'a'],
      ['2', 'x', 'NULL'],
    ];

    test('convertResultRowsToStringsSync maps rows correctly and deduplicates repeated cells', () {
      final rowsWithDuplicates = <List<Object?>>[
        ['active', 1, true, 'US'],
        ['active', 1, true, 'US'],
        ['active', 2, false, 'EU'],
      ];

      final out = convertResultRowsToStringsSync(rowsWithDuplicates);
      expect(out.length, 3);
      expect(out[0], ['active', '1', 'true', 'US']);
      expect(out[1], ['active', '1', 'true', 'US']);
      expect(out[2], ['active', '2', 'false', 'EU']);

      // Deduplicated string references must be identical pointers
      expect(identical(out[0][0], out[1][0]), isTrue);
      expect(identical(out[0][1], out[1][1]), isTrue);
      expect(identical(out[0][2], out[1][2]), isTrue);
      expect(identical(out[0][3], out[1][3]), isTrue);
    });

    test('convertResultRowsToStringsCompute maps rows correctly', () {
      expect(convertResultRowsToStringsCompute(sampleRows), expectedOutput);
      expect(convertResultRowsToStringsCompute(const []), isEmpty);
    });

    test('convertResultRowsToStringsYielding maps null to NULL and yields', () async {
      final out = await convertResultRowsToStringsYielding(
        sampleRows,
        yieldEvery: 1,
      );
      expect(out, expectedOutput);
      expect(await convertResultRowsToStringsYielding(const []), isEmpty);
    });

    test('convertResultRowsToStringsAdaptive handles small payload via yielding', () async {
      final out = await convertResultRowsToStringsAdaptive(
        sampleRows,
        computeThreshold: 100,
      );
      expect(out, expectedOutput);
      expect(await convertResultRowsToStringsAdaptive(const []), isEmpty);
    });

    test('convertResultRowsToStringsAdaptive handles large payload via compute', () async {
      final largeRows = List<List<Object?>>.generate(
        10,
        (i) => [i, null, 'val_$i'],
      );
      final out = await convertResultRowsToStringsAdaptive(
        largeRows,
        computeThreshold: 5,
      );
      expect(out.length, 10);
      expect(out[0], ['0', 'NULL', 'val_0']);
      expect(out[9], ['9', 'NULL', 'val_9']);
    });

    test('benchmark 10,000 low-cardinality rows demonstrates pointer reuse', () {
      final statuses = ['active', 'pending', 'cancelled', 'completed'];
      final countries = ['US', 'DE', 'FR', 'GB', 'JP'];

      final dataset = List<List<Object?>>.generate(
        10000,
        (i) => [
          i % 10,
          statuses[i % statuses.length],
          countries[i % countries.length],
          i % 2 == 0,
          null,
        ],
      );

      final stopwatch = Stopwatch()..start();
      final result = convertResultRowsToStringsSync(dataset);
      stopwatch.stop();

      expect(result.length, 10000);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));

      // Pointer verification
      expect(identical(result[0][1], result[4][1]), isTrue);
      expect(identical(result[0][2], result[5][2]), isTrue);
      expect(identical(result[0][3], result[2][3]), isTrue);
      expect(identical(result[0][4], result[1][4]), isTrue);
    });
  });
}
