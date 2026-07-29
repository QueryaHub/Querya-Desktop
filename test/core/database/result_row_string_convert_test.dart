import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';

void main() {
  group('result_row_string_convert', () {
    final sampleRows = <List<Object?>>[
      [1, null, 'a'],
      [2, 'x', null],
    ];

    final expectedOutput = [
      ['1', 'NULL', 'a'],
      ['2', 'x', 'NULL'],
    ];

    test('convertResultRowsToStringsSync maps rows correctly', () {
      expect(convertResultRowsToStringsSync(sampleRows), expectedOutput);
      expect(convertResultRowsToStringsSync(const []), isEmpty);
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
  });
}

