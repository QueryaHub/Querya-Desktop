import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:querya_desktop/features/mongodb/mongo_ejson.dart';
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

    test('ObjectId is hex, not ObjectId("…")', () {
      final id = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      expect(mongoFieldToDisplay(id), '507f1f77bcf86cd799439011');
      expect(mongoFieldToDisplay(id), isNot(contains('ObjectId(')));
    });

    test('DateTime is ISO-8601 UTC', () {
      final dt = DateTime.utc(2024, 6, 1, 12, 0, 0);
      expect(mongoFieldToDisplay(dt), '2024-06-01T12:00:00.000Z');
    });
  });

  group('mongoDisplayToValue', () {
    test('round-trips inspector strings without an original type', () {
      expect(mongoDisplayToValue('NULL'), isNull);
      expect(mongoDisplayToValue('true'), isTrue);
      expect(mongoDisplayToValue('false'), isFalse);
      expect(mongoDisplayToValue('Ada'), 'Ada');
      expect(mongoDisplayToValue('{"ok":true}'), {'ok': true});
      expect(mongoDisplayToValue('[1,2]'), [1, 2]);
      expect(mongoDisplayToValue('{not json'), '{not json');
    });

    test('numeric-looking strings stay strings', () {
      expect(mongoDisplayToValue('42', original: '42'), '42');
      expect(mongoDisplayToValue('42', original: '42'), isA<String>());
      expect(mongoDisplayToValue('02115', original: '02115'), '02115');
      expect(mongoDisplayToValue('3.5'), isA<String>());
    });

    test('int and double keep their width', () {
      expect(mongoDisplayToValue('42', original: 42), 42);
      expect(mongoDisplayToValue('42', original: 42), isA<int>());
      expect(mongoDisplayToValue('3.5', original: 3.5), 3.5);
      expect(mongoDisplayToValue('3.5', original: 3.5), isA<double>());
    });

    test('ObjectId round-trips from hex, shell literal, and \$oid', () {
      final id = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      expect(mongoDisplayToValue(mongoFieldToDisplay(id), original: id), id);
      expect(
        mongoDisplayToValue('ObjectId("507f1f77bcf86cd799439011")',
            original: id),
        id,
      );
      expect(
        mongoDisplayToValue(
          '{"\$oid":"507f1f77bcf86cd799439011"}',
          original: id,
        ),
        id,
      );
    });

    test('DateTime round-trips from ISO-8601', () {
      final dt = DateTime.utc(2024, 6, 1, 12, 0, 0);
      final back = mongoDisplayToValue(
        mongoFieldToDisplay(dt),
        original: dt,
      );
      expect(back, isA<DateTime>());
      expect((back as DateTime).toUtc(), dt);
    });

    test('Decimal128 round-trips', () {
      final original = mongoDocumentFromEjson(
        '{"v": {"\$numberDecimal": "10.50"}}',
      )['v'];
      expect(original, isNotNull);
      final display = mongoFieldToDisplay(original);
      final back = mongoDisplayToValue(display, original: original);
      expect(back.runtimeType, original.runtimeType);
      expect('$back', '$original');
    });

    test('Int64 round-trips', () {
      final original = mongoDocumentFromEjson(
        '{"v": {"\$numberLong": "9007199254740993"}}',
      )['v'];
      expect(original, isNotNull);
      final display = mongoFieldToDisplay(original);
      final back = mongoDisplayToValue(display, original: original);
      expect(back.runtimeType, original.runtimeType);
      expect('$back', '$original');
    });
  });

  group('mongoFieldIsReadOnly', () {
    test('blocks _id', () {
      expect(mongoFieldIsReadOnly('_id'), isTrue);
      expect(mongoFieldIsReadOnly('name'), isFalse);
      expect(() => mongoAssertFieldEditable('_id'), throwsStateError);
      expect(() => mongoAssertFieldEditable('name'), returnsNormally);
    });
  });
}
