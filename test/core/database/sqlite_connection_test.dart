import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('SqliteConnection Properties', () {
    test('stores basic constructor parameters correctly', () {
      final conn = SqliteConnection(
        id: 123,
        name: 'test_db',
        path: '/path/to/db.sqlite',
        readOnly: true,
      );
      expect(conn.id, 123);
      expect(conn.name, 'test_db');
      expect(conn.path, '/path/to/db.sqlite');
      expect(conn.readOnly, true);
      expect(conn.isConnected, false);
    });

    test('constructs from ConnectionRow correctly', () {
      const row = ConnectionRow(
        id: 456,
        type: 'sqlite',
        name: 'Row SQLite',
        host: '/another/path.sqlite',
        useSSL: true, // readOnly is mapped to useSSL
        createdAt: '',
      );
      final conn = SqliteConnection.fromConnectionRow(row);
      expect(conn.id, 456);
      expect(conn.name, 'Row SQLite');
      expect(conn.path, '/another/path.sqlite');
      expect(conn.readOnly, true);
    });
  });

  group('SqliteConnection operations (In-Memory)', () {
    late SqliteConnection conn;

    setUp(() {
      conn = SqliteConnection(
        id: 1,
        name: 'in_memory_test',
        path: inMemoryDatabasePath,
        readOnly: false,
      );
    });

    tearDown(() async {
      await conn.disconnect();
    });

    test('connects, executes raw query and disconnects', () async {
      expect(conn.isConnected, false);
      await conn.connect();
      expect(conn.isConnected, true);

      final res = await conn.execute('SELECT 42 AS val');
      expect(res, isNotEmpty);
      expect(res.first['val'], 42);

      await conn.disconnect();
      expect(conn.isConnected, false);
    });

    test('testConnection connects, queries and cleans up', () async {
      final ok = await conn.testConnection();
      expect(ok, true);
      expect(conn.isConnected, false); // should be disconnected afterwards
    });

    test('lists tables, views, and columns correctly', () async {
      await conn.connect();

      await conn.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');
      await conn.execute('CREATE VIEW user_names AS SELECT name FROM users');

      final tables = await conn.listTables();
      expect(tables, contains('users'));

      final views = await conn.listViews();
      expect(views, contains('user_names'));

      final columns = await conn.listColumnNames(table: 'users');
      expect(columns, containsAll(['id', 'name']));
    });

    test('throws StateError for modify operations in read-only mode', () async {
      final roConn = SqliteConnection(
        id: 2,
        name: 'in_memory_ro',
        path: inMemoryDatabasePath,
        readOnly: true,
      );

      await roConn.connect();

      // Queries should work
      final res = await roConn.execute('SELECT 100 AS num');
      expect(res.first['num'], 100);

      // Writes should throw StateError
      expect(
        () => roConn.execute('CREATE TABLE should_fail (id INT)'),
        throwsA(isA<StateError>()),
      );

      await roConn.disconnect();
    });

    test('handles quotes in quoteIdentifier helper', () {
      expect(SqliteConnection.quoteIdentifier('normal_table'), '"normal_table"');
      expect(SqliteConnection.quoteIdentifier('table"with"quotes'), '"table""with""quotes"');
    });
  });
}
