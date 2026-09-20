import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mongodb/mongo_field_codec.dart';

void main() {
  group('mongoFieldToDisplay', () {
    test('encodes null, scalars, and JSON structures', () {
      expect(mongoFieldToDisplay(null), 'NULL');
      expect(mongoFieldToDisplay(true), 'true');
      expect(mongoFieldToDisplay(42), '42');
      expect(mongoFieldToDisplay('Ada'), 'Ada');
      expect(
        mongoFieldToDisplay({'ok': true}),
        '{\n  "ok": true\n}',
      );
      expect(mongoFieldToDisplay([1, 2]), '[\n  1,\n  2\n]');
    });
  });

  group('mongoDisplayToValue', () {
    test('round-trips inspector strings', () {
      expect(mongoDisplayToValue('NULL'), isNull);
      expect(mongoDisplayToValue('true'), isTrue);
      expect(mongoDisplayToValue('false'), isFalse);
      expect(mongoDisplayToValue('3.5'), 3.5);
      expect(mongoDisplayToValue('Ada'), 'Ada');
      expect(mongoDisplayToValue('{"ok":true}'), {'ok': true});
      expect(mongoDisplayToValue('[1,2]'), [1, 2]);
      expect(mongoDisplayToValue('{not json'), '{not json');
    });
  });
}
