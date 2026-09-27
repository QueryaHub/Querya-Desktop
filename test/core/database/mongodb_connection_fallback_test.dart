import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';

void main() {
  group('MongoConnection.effectiveDatabase', () {
    test('returns database from property if configured', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        database: '  analytics_prod  ',
      );
      expect(conn.effectiveDatabase, 'analytics_prod');
    });

    test('returns database from connectionString URI path if database property is omitted', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        connectionString: 'mongodb://user:secret@mongo.cloud.com:27017/tenant_db?ssl=true',
      );
      expect(conn.effectiveDatabase, 'tenant_db');
    });

    test('returns null when neither property nor URI has a database', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(conn.effectiveDatabase, isNull);
    });
  });
}
