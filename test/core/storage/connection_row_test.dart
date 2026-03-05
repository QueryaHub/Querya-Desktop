import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

void main() {
  group('ConnectionRow', () {
    test('toMap produces correct keys and values', () {
      const row = ConnectionRow(
        type: 'mongodb',
        name: 'Test Mongo',
        host: 'mongo.example.com',
        port: 27017,
        username: 'admin',
        password: 's3cret',
        databaseName: 'mydb',
        authSource: 'admin',
        useSSL: true,
        connectionString: 'mongodb://custom',
        folderId: 5,
        sortOrder: 2,
        createdAt: '2026-01-01T00:00:00Z',
      );

      final map = row.toMap();

      expect(map['type'], 'mongodb');
      expect(map['name'], 'Test Mongo');
      expect(map['host'], 'mongo.example.com');
      expect(map['port'], 27017);
      expect(map['username'], 'admin');
      expect(map['password'], 's3cret');
      expect(map['database_name'], 'mydb');
      expect(map['auth_source'], 'admin');
      expect(map['use_ssl'], 1); // bool → int
      expect(map['connection_string'], 'mongodb://custom');
      expect(map['folder_id'], 5);
      expect(map['sort_order'], 2);
      expect(map['created_at'], '2026-01-01T00:00:00Z');
    });

    test('toMap encodes useSSL=false as 0', () {
      const row = ConnectionRow(
        type: 'redis',
        name: 'Redis',
        createdAt: '2026-01-01T00:00:00Z',
      );
      expect(row.toMap()['use_ssl'], 0);
    });

    test('fromMap restores all fields correctly', () {
      final map = <String, Object?>{
        'id': 42,
        'type': 'redis',
        'name': 'My Redis',
        'host': 'redis.local',
        'port': 6379,
        'username': 'default',
        'password': 'pass',
        'database_name': null,
        'auth_source': null,
        'use_ssl': 0,
        'connection_string': null,
        'folder_id': 3,
        'sort_order': 1,
        'created_at': '2026-03-01T12:00:00Z',
      };

      final row = ConnectionRow.fromMap(map);

      expect(row.id, 42);
      expect(row.type, 'redis');
      expect(row.name, 'My Redis');
      expect(row.host, 'redis.local');
      expect(row.port, 6379);
      expect(row.username, 'default');
      expect(row.password, 'pass');
      expect(row.databaseName, isNull);
      expect(row.authSource, isNull);
      expect(row.useSSL, false);
      expect(row.connectionString, isNull);
      expect(row.folderId, 3);
      expect(row.sortOrder, 1);
      expect(row.createdAt, '2026-03-01T12:00:00Z');
    });

    test('fromMap decodes use_ssl=1 as true', () {
      final map = <String, Object?>{
        'id': 1,
        'type': 'mongodb',
        'name': 'SSL Mongo',
        'host': 'h',
        'port': 27017,
        'use_ssl': 1,
        'sort_order': 0,
        'created_at': '2026-01-01T00:00:00Z',
      };

      final row = ConnectionRow.fromMap(map);
      expect(row.useSSL, true);
    });

    test('round-trip: toMap -> fromMap preserves data', () {
      const original = ConnectionRow(
        type: 'mongodb',
        name: 'Round Trip',
        host: 'localhost',
        port: 27017,
        username: 'u',
        password: 'p',
        databaseName: 'testdb',
        authSource: 'admin',
        useSSL: true,
        connectionString: 'mongodb://localhost/testdb',
        folderId: 10,
        sortOrder: 5,
        createdAt: '2026-06-15T09:30:00Z',
      );

      // Simulate DB round-trip: toMap -> add id -> fromMap
      final map = original.toMap();
      map['id'] = 99;

      final restored = ConnectionRow.fromMap(map);

      expect(restored.id, 99);
      expect(restored.type, original.type);
      expect(restored.name, original.name);
      expect(restored.host, original.host);
      expect(restored.port, original.port);
      expect(restored.username, original.username);
      expect(restored.password, original.password);
      expect(restored.databaseName, original.databaseName);
      expect(restored.authSource, original.authSource);
      expect(restored.useSSL, original.useSSL);
      expect(restored.connectionString, original.connectionString);
      expect(restored.folderId, original.folderId);
      expect(restored.sortOrder, original.sortOrder);
      expect(restored.createdAt, original.createdAt);
    });

    test('fromMap handles missing optional fields gracefully', () {
      final map = <String, Object?>{
        'type': 'postgresql',
        'name': 'PG Minimal',
        'created_at': '2026-01-01T00:00:00Z',
      };

      final row = ConnectionRow.fromMap(map);

      expect(row.id, isNull);
      expect(row.host, isNull);
      expect(row.port, isNull);
      expect(row.username, isNull);
      expect(row.password, isNull);
      expect(row.databaseName, isNull);
      expect(row.authSource, isNull);
      expect(row.useSSL, false); // null use_ssl → false
      expect(row.connectionString, isNull);
      expect(row.folderId, isNull);
      expect(row.sortOrder, 0); // null sort_order → 0
    });

    test('toMap does not include id field', () {
      const row = ConnectionRow(
        id: 123,
        type: 'redis',
        name: 'R',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final map = row.toMap();
      expect(map.containsKey('id'), false);
    });
  });
}
