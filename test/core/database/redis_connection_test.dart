import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

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

    test('forceClose delegates to disconnect cleanly', () async {
      final conn = RedisConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      await conn.forceClose();
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

  group('RedisConnection.fromConnectionRow', () {
    test('parses rediss URI and SSL flag', () {
      final conn = RedisConnection.fromConnectionRow(
        const ConnectionRow(
          id: 3,
          type: 'redis',
          name: 'secure-redis',
          host: 'localhost',
          port: 6379,
          useSSL: true,
          connectionString:
              'rediss://user:pass@cache.example.com:6380?sslrootcert=%2Fca.pem',
          createdAt: '0',
        ),
      );
      expect(conn.useSSL, isTrue);
      expect(conn.host, 'cache.example.com');
      expect(conn.port, 6380);
      expect(conn.username, 'user');
      expect(conn.password, 'pass');
      expect(conn.connectionString, contains('sslrootcert'));
    });

    test('URI-only row (null host/port) still uses URI host, port, and TLS',
        () {
      final conn = RedisConnection.fromConnectionRow(
        const ConnectionRow(
          id: 8,
          type: 'redis',
          name: 'uri-only',
          useSSL: false,
          connectionString:
              'rediss://user:s3cret@cache.example.com:6380?sslrootcert=%2Fca.pem',
          createdAt: '0',
        ),
      );
      expect(conn.host, 'cache.example.com');
      expect(conn.port, 6380);
      expect(conn.useSSL, isTrue);
      expect(conn.username, 'user');
      expect(conn.password, 's3cret');
      expect(conn.connectionString, contains('sslrootcert'));
    });

    test('sidebar probe id override does not use the saved connection id', () {
      final conn = RedisConnection.fromConnectionRow(
        const ConnectionRow(
          id: 42,
          type: 'redis',
          name: 'prod',
          connectionString: 'rediss://cache.example.com:6380',
          createdAt: '0',
        ),
        id: -1,
      );
      expect(conn.id, -1);
      expect(conn.host, 'cache.example.com');
      expect(conn.port, 6380);
      expect(conn.useSSL, isTrue);
    });

    test('host/port form without URI stays on those fields', () {
      final conn = RedisConnection.fromConnectionRow(
        const ConnectionRow(
          type: 'redis',
          name: 'local',
          host: '127.0.0.1',
          port: 6379,
          useSSL: false,
          createdAt: '0',
        ),
      );
      expect(conn.host, '127.0.0.1');
      expect(conn.port, 6379);
      expect(conn.useSSL, isFalse);
    });
  });

  group('RedisConnectionException', () {
    test('stores message and toString returns it', () {
      final ex = RedisConnectionException('something went wrong');
      expect(ex.message, 'something went wrong');
      expect(ex.toString(), 'something went wrong');
    });
  });

  group('RedisConnection clientReadOnly', () {
    test('SET and DEL throw while the session lock is on', () async {
      final fake = RedisConnectionTestFake();
      await fake.connect();
      await fake.applyClientReadOnly(true);

      expect(fake.clientReadOnly, isTrue);
      await expectLater(
        fake.set('k', 'v'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Redis connection is read-only',
          ),
        ),
      );
      await expectLater(fake.del('k'), throwsA(isA<StateError>()));

      await fake.applyClientReadOnly(false);
      expect(fake.clientReadOnly, isFalse);
      expect(await fake.del('k'), 0);
      await fake.disconnect();
    });
  });

  group('RedisConnection collection paging', () {
    test('LRANGE first page is capped and HGETALL is refused by the fake',
        () async {
      final fake = RedisConnectionTestFake(
        listItems: List.generate(250, (i) => 'item_$i'),
      );
      await fake.connect();

      final page = await fake.lrange('k', 0, redisCollectionPageSize - 1);
      expect(page, hasLength(redisCollectionPageSize));
      expect(page.first, 'item_0');
      expect(page.last, 'item_199');
      expect(await fake.llen('k'), 250);
      await expectLater(fake.hgetall('k'), throwsStateError);
      await fake.disconnect();
    });

    test('HSCAN returns pages instead of HGETALL', () async {
      final fake = RedisConnectionTestFake(
        hashFirstPage: const {'a': '1', 'b': '2'},
        hashSecondPage: const {'c': '3'},
      );
      await fake.connect();

      final (c1, p1) = await fake.hscan('h');
      expect(c1, 1);
      expect(p1, {'a': '1', 'b': '2'});
      final (c2, p2) = await fake.hscan('h', cursor: c1);
      expect(c2, 0);
      expect(p2, {'c': '3'});
      expect(await fake.hlen('h'), 3);
      await fake.disconnect();
    });
  });
}
