import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/util/deep_collection_equals.dart';
import 'package:querya_desktop/features/mysql/mysql_result_utils.dart';

void main() {
  group('deepCollectionEquals', () {
    test('compares nested maps and lists', () {
      const a = {
        'x': 1,
        'y': [
          1,
          2,
          {'z': 'ok'}
        ],
      };
      const b = {
        'x': 1,
        'y': [
          1,
          2,
          {'z': 'ok'}
        ],
      };
      const c = {
        'x': 1,
        'y': [
          1,
          2,
          {'z': 'nope'}
        ],
      };
      expect(deepCollectionEquals(a, b), isTrue);
      expect(deepCollectionEquals(a, c), isFalse);
    });

    test('replaceIfChanged skips identical snapshots', () {
      var value = {'a': 1};
      var applyCount = 0;
      expect(
        replaceIfChanged(value, {'a': 1}, (v) {
          applyCount++;
          value = v!;
        }),
        isFalse,
      );
      expect(applyCount, 0);
    });
  });

  group('convertMysqlResultRowsToStrings', () {
    test('null cells become NULL', () {
      final out = convertMysqlResultRowsToStrings(
        const MysqlResultConvertJob(
          rowValues: [
            [1, null, 'x'],
          ],
        ),
      );
      expect(out, [
        ['1', 'NULL', 'x'],
      ]);
    });
  });
}
