import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

void main() {
  group('MongoService.createConnection', () {
    test('creates MongoConnection from ConnectionRow', () {
      const row = ConnectionRow(
        id: 10,
        type: 'mongodb',
        name: 'My Mongo',
        host: 'mongo.local',
        port: 27018,
        username: 'root',
        password: 'secret',
        databaseName: 'testdb',
        authSource: 'admin',
        useSSL: true,
        connectionString: 'mongodb://custom',
        createdAt: '2026-01-01T00:00:00Z',
      );

      final conn = MongoService.instance.createConnection(row);

      expect(conn.id, 10);
      expect(conn.name, 'My Mongo');
      expect(conn.host, 'mongo.local');
      expect(conn.port, 27018);
      expect(conn.username, 'root');
      expect(conn.password, 'secret');
      expect(conn.database, 'testdb');
      expect(conn.authSource, 'admin');
      expect(conn.useSSL, true);
      expect(conn.connectionString, 'mongodb://custom');
      expect(conn.isConnected, false);
    });

    test('uses default host and port when null', () {
      const row = ConnectionRow(
        id: 1,
        type: 'mongodb',
        name: 'Defaults',
        createdAt: '2026-01-01T00:00:00Z',
      );

      final conn = MongoService.instance.createConnection(row);

      expect(conn.host, 'localhost');
      expect(conn.port, 27017);
    });

    test('uses id=0 when ConnectionRow.id is null', () {
      const row = ConnectionRow(
        type: 'mongodb',
        name: 'No ID',
        createdAt: '2026-01-01T00:00:00Z',
      );

      final conn = MongoService.instance.createConnection(row);
      expect(conn.id, 0);
    });

    test('throws ArgumentError for non-mongodb type', () {
      const row = ConnectionRow(
        id: 1,
        type: 'redis',
        name: 'Redis',
        createdAt: '2026-01-01T00:00:00Z',
      );

      expect(
        () => MongoService.instance.createConnection(row),
        throwsArgumentError,
      );
    });

    test('replaces existing connection with same ID', () {
      const row1 = ConnectionRow(
        id: 88,
        type: 'mongodb',
        name: 'First',
        host: 'host1',
        createdAt: '2026-01-01T00:00:00Z',
      );
      const row2 = ConnectionRow(
        id: 88,
        type: 'mongodb',
        name: 'Second',
        host: 'host2',
        createdAt: '2026-01-01T00:00:00Z',
      );

      MongoService.instance.createConnection(row1);
      final conn2 = MongoService.instance.createConnection(row2);

      final stored = MongoService.instance.getConnection(88);
      expect(stored, same(conn2));
      expect(stored?.name, 'Second');
      expect(stored?.host, 'host2');
    });
  });

  group('MongoService.getConnection', () {
    test('returns connection by ID', () {
      const row = ConnectionRow(
        id: 55,
        type: 'mongodb',
        name: 'Findable',
        createdAt: '2026-01-01T00:00:00Z',
      );

      final created = MongoService.instance.createConnection(row);
      final found = MongoService.instance.getConnection(55);

      expect(found, same(created));
    });

    test('returns null for unknown ID', () {
      expect(MongoService.instance.getConnection(999998), isNull);
    });
  });

  group('MongoService.disconnectAll', () {
    test('completes when no connections', () async {
      await MongoService.instance.disconnectAll();
    });

    test('clears all tracked connections', () async {
      MongoService.instance.createConnection(
        const ConnectionRow(
          id: 301,
          type: 'mongodb',
          name: 'a',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );
      MongoService.instance.createConnection(
        const ConnectionRow(
          id: 302,
          type: 'mongodb',
          name: 'b',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );
      expect(MongoService.instance.getConnection(301), isNotNull);
      expect(MongoService.instance.getConnection(302), isNotNull);

      await MongoService.instance.disconnectAll();

      expect(MongoService.instance.getConnection(301), isNull);
      expect(MongoService.instance.getConnection(302), isNull);
    });
  });
}
