import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:querya_desktop/features/mongodb/mongo_ejson.dart';

void main() {
  group('mongoDocumentToEjson / mongoDocumentFromEjson', () {
    test('round-trips ObjectId _id and DateTime', () {
      final id = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      final created = DateTime.utc(2024, 1, 15, 12, 30, 0);
      final doc = <String, dynamic>{
        '_id': id,
        'created': created,
        'name': 'Ada',
      };

      final json = mongoDocumentToEjson(doc);
      expect(json, contains(r'$oid'));
      expect(json, contains('507f1f77bcf86cd799439011'));
      expect(json, contains(r'$date'));
      expect(json, isNot(contains('ObjectId(')));

      final back = mongoDocumentFromEjson(json);
      expect(back['_id'], isA<ObjectId>());
      expect((back['_id'] as ObjectId).oid, id.oid);
      expect(back['created'], isA<DateTime>());
      expect(
        (back['created'] as DateTime).toUtc(),
        created,
      );
      expect(back['name'], 'Ada');
    });

    test('_id filter value keeps BSON ObjectId, not a string', () {
      final id = ObjectId.fromHexString('507f191e810c19729de860ea');
      final json = mongoDocumentToEjson({'_id': id, 'n': 1});
      final back = mongoDocumentFromEjson(json);
      expect(back['_id'], isA<ObjectId>());
      expect(back['_id'], isNot(isA<String>()));
    });

    test('relaxed EJSON keeps plain numbers and strings', () {
      final json = mongoDocumentToEjson({'a': 1, 'b': 'x'});
      expect(json, contains('"a"'));
      expect(json, contains('1'));
      expect(json, isNot(contains(r'$numberInt')));
      final back = mongoDocumentFromEjson(json);
      expect(back['a'], 1);
      expect(back['b'], 'x');
    });

    test('rejects a JSON array', () {
      expect(
        () => mongoDocumentFromEjson('[1, 2]'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('mongoFilterFromJson', () {
    test('24-char hex _id becomes ObjectId, not a String', () {
      const hex = '507f1f77bcf86cd799439011';
      final filter = mongoFilterFromJson('{"_id": "$hex"}');
      expect(filter['_id'], isA<ObjectId>());
      expect(filter['_id'], isNot(isA<String>()));
      expect((filter['_id'] as ObjectId).oid, hex);
      expect(mongoFilterNeedsObjectIdHint(filter), isFalse);
    });

    test('Extended JSON \$oid _id is ObjectId', () {
      const hex = '507f191e810c19729de860ea';
      final filter = mongoFilterFromJson(
        '{"_id": {"\$oid": "$hex"}}',
      );
      expect(filter['_id'], isA<ObjectId>());
      expect((filter['_id'] as ObjectId).oid, hex);
    });

    test('Extended JSON \$date is DateTime', () {
      final filter = mongoFilterFromJson(
        '{"created": {"\$date": "2024-01-15T12:30:00.000Z"}}',
      );
      expect(filter['created'], isA<DateTime>());
      expect(
        (filter['created'] as DateTime).toUtc(),
        DateTime.utc(2024, 1, 15, 12, 30),
      );
    });

    test('non-hex _id string stays a string and needs the ObjectId hint', () {
      final filter = mongoFilterFromJson('{"_id": "not-an-objectid"}');
      expect(filter['_id'], 'not-an-objectid');
      expect(mongoFilterNeedsObjectIdHint(filter), isTrue);
    });

    test('query operators like \$gt are kept', () {
      final filter = mongoFilterFromJson('{"age": {"\$gt": 5}}');
      expect(filter['age'], isA<Map>());
      expect((filter['age'] as Map)[r'$gt'], 5);
    });
  });
}
