import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mongodb/mongo_index_info.dart';

void main() {
  group('MongoIndexInfo tests', () {
    test('identifies primary index correctly and forbids deletion', () {
      final primary = MongoIndexInfo.fromMap({
        'name': '_id_',
        'key': {'_id': 1},
        'size': 16384,
      });

      expect(primary.isPrimary, isTrue);
      expect(primary.indexType, equals('Primary'));
      expect(primary.sizeFormatted, equals('16.0 KB'));
    });

    test('categorizes compound and single field indexes', () {
      final single = MongoIndexInfo.fromMap({
        'name': 'status_1',
        'key': {'status': 1},
        'size': 8192,
      });
      expect(single.isPrimary, isFalse);
      expect(single.indexType, equals('Single Field'));
      expect(single.keysFormatted, equals('status: 1'));

      final compound = MongoIndexInfo.fromMap({
        'name': 'user_1_created_-1',
        'key': {'userId': 1, 'createdAt': -1},
        'size': 32768,
        'unique': true,
      });
      expect(compound.isPrimary, isFalse);
      expect(compound.indexType, equals('Compound'));
      expect(compound.isUnique, isTrue);
      expect(compound.keysFormatted, equals('userId: 1, createdAt: -1'));
      expect(compound.sizeFormatted, equals('32.0 KB'));
    });

    test('categorizes TTL index when expireAfterSeconds is set', () {
      final ttl = MongoIndexInfo.fromMap({
        'name': 'session_expire',
        'key': {'createdAt': 1},
        'expireAfterSeconds': 3600,
        'size': 4096,
      });
      expect(ttl.isTtl, isTrue);
      expect(ttl.indexType, equals('TTL'));
      expect(ttl.expireAfterSeconds, equals(3600));
    });

    test('categorizes text and geospatial indexes', () {
      final textIdx = MongoIndexInfo.fromMap({
        'name': 'title_text',
        'key': {'title': 'text'},
      });
      expect(textIdx.indexType, equals('Text'));

      final geoIdx = MongoIndexInfo.fromMap({
        'name': 'loc_2dsphere',
        'key': {'location': '2dsphere'},
      });
      expect(geoIdx.indexType, equals('Geospatial'));
    });

    test('size formatting formats bytes, KB, MB, and GB', () {
      expect(const MongoIndexInfo(name: 'a', keys: {}).sizeFormatted, equals('—'));
      expect(const MongoIndexInfo(name: 'a', keys: {}, sizeBytes: 512).sizeFormatted, equals('512 B'));
      expect(const MongoIndexInfo(name: 'a', keys: {}, sizeBytes: 2048).sizeFormatted, equals('2.0 KB'));
      expect(const MongoIndexInfo(name: 'a', keys: {}, sizeBytes: 5242880).sizeFormatted, equals('5.0 MB'));
    });
  });
}
