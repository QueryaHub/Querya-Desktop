import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';

void main() {
  group('RedisConnection initial state', () {
    test('isConnected is false before connect()', () {
      final conn = RedisConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(conn.isConnected, false);
    });

    test('default port is 6379', () {
      final conn = RedisConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(conn.port, 6379);
    });

    test('custom port is stored', () {
      final conn = RedisConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        port: 6380,
      );
      expect(conn.port, 6380);
    });

    test('stores all constructor parameters', () {
      final conn = RedisConnection(
        id: 42,
        name: 'My Redis',
        host: 'redis.local',
        port: 6380,
        username: 'admin',
        password: 's3cret',
      );
      expect(conn.id, 42);
      expect(conn.name, 'My Redis');
      expect(conn.host, 'redis.local');
      expect(conn.port, 6380);
      expect(conn.username, 'admin');
      expect(conn.password, 's3cret');
    });

    test('username and password default to null', () {
      final conn = RedisConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(conn.username, isNull);
      expect(conn.password, isNull);
    });
  });

  group('RedisConnection.disconnect', () {
    test('disconnect on a never-connected instance does not throw', () async {
      final conn = RedisConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      // Should complete without error
      await conn.disconnect();
      expect(conn.isConnected, false);
    });

    test('double disconnect does not throw', () async {
      final conn = RedisConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      await conn.disconnect();
      await conn.disconnect();
      expect(conn.isConnected, false);
    });
  });

  group('RedisConnection.info', () {
    test('throws StateError when not connected', () {
      final conn = RedisConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(() => conn.info(), throwsStateError);
    });
  });

  group('RedisConnectionException', () {
    test('stores message and toString returns it', () {
      final ex = RedisConnectionException('something went wrong');
      expect(ex.message, 'something went wrong');
      expect(ex.toString(), 'something went wrong');
    });
  });
}
