import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';

void main() {
  group('convertResultRowsToStringsYielding', () {
    test('maps null to NULL and yields without isolate', () async {
      final rows = <List<Object?>>[
        [1, null, 'a'],
        [2, 'x', null],
      ];
      final out = await convertResultRowsToStringsYielding(
        rows,
        yieldEvery: 1,
      );
      expect(out, [
        ['1', 'NULL', 'a'],
        ['2', 'x', 'NULL'],
      ]);
    });

    test('empty input returns empty', () async {
      expect(await convertResultRowsToStringsYielding(const []), isEmpty);
    });
  });
}
