import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';

void main() {
  group('PostgresConnection initial state', () {
    test('isConnected is false before connect()', () {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(conn.isConnected, false);
    });

    test('default port is 5432', () {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(conn.port, 5432);
    });

    test('default useSSL is false', () {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(conn.useSSL, false);
    });

    test('custom port and useSSL are stored', () {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        port: 5433,
        useSSL: true,
      );
      expect(conn.port, 5433);
      expect(conn.useSSL, true);
    });

    test('stores all constructor parameters', () {
      final conn = PostgresConnection(
        id: 42,
        name: 'My PostgreSQL',
        host: 'pg.example.com',
        port: 5433,
        username: 'admin',
        password: 's3cret',
        database: 'appdb',
        useSSL: true,
      );
      expect(conn.id, 42);
      expect(conn.name, 'My PostgreSQL');
      expect(conn.host, 'pg.example.com');
      expect(conn.port, 5433);
      expect(conn.username, 'admin');
      expect(conn.password, 's3cret');
      expect(conn.database, 'appdb');
      expect(conn.useSSL, true);
    });

    test('username, password, database default to null', () {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(conn.username, isNull);
      expect(conn.password, isNull);
      expect(conn.database, isNull);
    });

    test('connectionString is stored when provided', () {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        connectionString: 'postgresql://user:pass@host/db',
      );
      expect(conn.connectionString, 'postgresql://user:pass@host/db');
    });

    test('connectionString defaults to null', () {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(conn.connectionString, isNull);
    });
  });

  group('PostgresConnection.disconnect', () {
    test('disconnect on a never-connected instance does not throw', () async {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      await conn.disconnect();
      expect(conn.isConnected, false);
    });

    test('double disconnect does not throw', () async {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      await conn.disconnect();
      await conn.disconnect();
      expect(conn.isConnected, false);
    });
  });

  group('PostgresConnection when not connected', () {
    late PostgresConnection conn;

    setUp(() {
      conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
    });

    test('execute throws StateError', () {
      expect(
        () => conn.execute('SELECT 1'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });

    test('listDatabases throws StateError', () {
      expect(
        () => conn.listDatabases(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });

    test('listSchemas throws StateError', () {
      expect(
        () => conn.listSchemas(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });

    test('listTables throws StateError', () {
      expect(
        () => conn.listTables(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });

    test('listViews throws StateError', () {
      expect(
        () => conn.listViews(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });

    test('listFunctions throws StateError', () {
      expect(
        () => conn.listFunctions(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });

    test('listSequences throws StateError', () {
      expect(
        () => conn.listSequences(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });

    test('serverVersion throws StateError', () {
      expect(
        () => conn.serverVersion(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });

    test('serverStats throws StateError', () {
      expect(
        () => conn.serverStats(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });

    test('getFunctionDefinitions throws StateError', () {
      expect(
        () => conn.getFunctionDefinitions('public', 'foo'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });

    test('getSequenceDetails throws StateError', () {
      expect(
        () => conn.getSequenceDetails('public', 'foo'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to PostgreSQL'),
        )),
      );
    });
  });

  group('PostgresConnection.connectToDatabase', () {
    test('returns new PostgresConnection with same params and given database', () async {
      final conn = PostgresConnection(
        id: 10,
        name: 'Server',
        host: 'pg.local',
        port: 5433,
        username: 'u',
        password: 'p',
        database: 'postgres',
        useSSL: true,
      );
      final newConn = await conn.connectToDatabase('otherdb');

      expect(newConn.id, conn.id);
      expect(newConn.name, conn.name);
      expect(newConn.host, conn.host);
      expect(newConn.port, conn.port);
      expect(newConn.username, conn.username);
      expect(newConn.password, conn.password);
      expect(newConn.useSSL, conn.useSSL);
      expect(newConn.database, 'otherdb');
      expect(newConn.isConnected, false);
    });

    test('original connection is unchanged', () async {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        database: 'mydb',
      );
      await conn.connectToDatabase('other');
      expect(conn.database, 'mydb');
    });

    test('returned connection has connectionString null', () async {
      final conn = PostgresConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        connectionString: 'postgresql://u:p@h/db',
      );
      final newConn = await conn.connectToDatabase('targetdb');
      expect(newConn.connectionString, isNull);
      expect(newConn.database, 'targetdb');
    });
  });

  group('PostgresConnectionException', () {
    test('stores message and toString returns it', () {
      final ex = PostgresConnectionException('connection refused');
      expect(ex.message, 'connection refused');
      expect(ex.toString(), 'connection refused');
    });
  });
}
