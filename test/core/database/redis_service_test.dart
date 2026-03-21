import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

void main() {
  group('RedisService.createConnection', () {
    test('creates RedisConnection from ConnectionRow', () {
      const row = ConnectionRow(
        id: 10,
        type: 'redis',
        name: 'My Redis',
        host: 'redis.local',
        port: 6380,
        username: 'admin',
        password: 's3cret',
        createdAt: '2026-01-01T00:00:00Z',
      );

      final conn = RedisService.instance.createConnection(row);

      expect(conn.id, 10);
      expect(conn.name, 'My Redis');
      expect(conn.host, 'redis.local');
      expect(conn.port, 6380);
      expect(conn.username, 'admin');
      expect(conn.password, 's3cret');
      expect(conn.isConnected, false);
    });

    test('uses default host and port when null', () {
      const row = ConnectionRow(
        id: 1,
        type: 'redis',
        name: 'Defaults',
        createdAt: '2026-01-01T00:00:00Z',
      );

      final conn = RedisService.instance.createConnection(row);

      expect(conn.host, 'localhost');
      expect(conn.port, 6379);
    });

    test('uses id=0 when ConnectionRow.id is null', () {
      const row = ConnectionRow(
        type: 'redis',
        name: 'No ID',
        createdAt: '2026-01-01T00:00:00Z',
      );

      final conn = RedisService.instance.createConnection(row);
      expect(conn.id, 0);
    });

    test('throws ArgumentError for non-redis type', () {
      const row = ConnectionRow(
        id: 1,
        type: 'mongodb',
        name: 'Mongo',
        createdAt: '2026-01-01T00:00:00Z',
      );

      expect(
        () => RedisService.instance.createConnection(row),
        throwsArgumentError,
      );
    });

    test('replaces existing connection with same ID', () {
      const row1 = ConnectionRow(
        id: 99,
        type: 'redis',
        name: 'First',
        host: 'host1',
        createdAt: '2026-01-01T00:00:00Z',
      );
      const row2 = ConnectionRow(
        id: 99,
        type: 'redis',
        name: 'Second',
        host: 'host2',
        createdAt: '2026-01-01T00:00:00Z',
      );

      RedisService.instance.createConnection(row1);
      final conn2 = RedisService.instance.createConnection(row2);

      // The service should now hold the second connection
      final stored = RedisService.instance.getConnection(99);
      expect(stored, same(conn2));
      expect(stored?.name, 'Second');
      expect(stored?.host, 'host2');
    });
  });

  group('RedisService.getConnection', () {
    test('returns connection by ID', () {
      const row = ConnectionRow(
        id: 50,
        type: 'redis',
        name: 'Findable',
        createdAt: '2026-01-01T00:00:00Z',
      );

      final created = RedisService.instance.createConnection(row);
      final found = RedisService.instance.getConnection(50);

      expect(found, same(created));
    });

    test('returns null for unknown ID', () {
      expect(RedisService.instance.getConnection(999999), isNull);
    });
  });

  group('RedisService.disconnect', () {
    test('removes connection from service after disconnect', () async {
      const row = ConnectionRow(
        id: 77,
        type: 'redis',
        name: 'ToDisconnect',
        createdAt: '2026-01-01T00:00:00Z',
      );

      final conn = RedisService.instance.createConnection(row);
      expect(RedisService.instance.getConnection(77), isNotNull);

      await RedisService.instance.disconnect(conn);
      expect(RedisService.instance.getConnection(77), isNull);
    });
  });

  group('RedisService.disconnectAll', () {
    test('completes when no connections', () async {
      await RedisService.instance.disconnectAll();
    });

    test('clears all tracked connections', () async {
      RedisService.instance.createConnection(
        const ConnectionRow(
          id: 201,
          type: 'redis',
          name: 'a',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );
      RedisService.instance.createConnection(
        const ConnectionRow(
          id: 202,
          type: 'redis',
          name: 'b',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );
      expect(RedisService.instance.getConnection(201), isNotNull);
      expect(RedisService.instance.getConnection(202), isNotNull);

      await RedisService.instance.disconnectAll();

      expect(RedisService.instance.getConnection(201), isNull);
      expect(RedisService.instance.getConnection(202), isNull);
    });
  });
}
