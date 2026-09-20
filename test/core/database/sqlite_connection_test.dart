import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/sqlite/sqlite_table_utils.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/table_view_staging.dart';

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

  group('sqliteOpenReadOnly', () {
    const rw = ConnectionRow(
      id: 1,
      type: 'sqlite',
      name: 'rw',
      host: '/tmp/rw.db',
      createdAt: '',
    );
    const formRo = ConnectionRow(
      id: 2,
      type: 'sqlite',
      name: 'ro',
      host: '/tmp/ro.db',
      useSSL: true,
      createdAt: '',
    );

    test('form read-only opens SQLITE_OPEN_READONLY even for tableWrite', () {
      expect(
        sqliteOpenReadOnly(row: formRo, mode: SqliteSessionMode.tableWrite),
        isTrue,
      );
      expect(
        sqliteOpenReadOnly(row: formRo, mode: SqliteSessionMode.readWrite),
        isTrue,
      );
    });

    test('writable form uses read-write only for tableWrite/readWrite', () {
      expect(
        sqliteOpenReadOnly(row: rw, mode: SqliteSessionMode.readOnly),
        isTrue,
      );
      expect(
        sqliteOpenReadOnly(row: rw, mode: SqliteSessionMode.tableWrite),
        isFalse,
      );
      expect(
        sqliteOpenReadOnly(row: rw, mode: SqliteSessionMode.readWrite),
        isFalse,
      );
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

    test('configures PRAGMA busy_timeout to 5000 on connection open', () async {
      await conn.connect();
      final res = await conn.execute('PRAGMA busy_timeout');
      expect(res, isNotEmpty);
      expect(res.first['timeout'], 5000);
    });

    test('enables WAL on a file database', () async {
      final dir = await Directory.systemTemp.createTemp('querya_sqlite_wal_');
      final path = '${dir.path}/t.db';
      final fileConn = SqliteConnection(
        id: 9,
        name: 'wal_file',
        path: path,
        createIfMissing: true,
      );
      addTearDown(() async {
        await fileConn.disconnect();
        await dir.delete(recursive: true);
      });
      await fileConn.connect();
      final res = await fileConn.execute('PRAGMA journal_mode');
      expect(
        res.first['journal_mode']?.toString().toLowerCase(),
        'wal',
      );
    });

    test('testConnection connects, queries and cleans up', () async {
      final result = await conn.testConnection();
      expect(result.ok, isTrue);
      expect(conn.isConnected, false); // should be disconnected afterwards
    });

    test('lists tables, views, and columns correctly', () async {
      await conn.connect();

      await conn
          .execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');
      await conn.execute('CREATE VIEW user_names AS SELECT name FROM users');

      final tables = await conn.listTables();
      expect(tables, contains('users'));

      final views = await conn.listViews();
      expect(views, contains('user_names'));

      final columns = await conn.listColumnNames(table: 'users');
      expect(columns, containsAll(['id', 'name']));
    });

    test('Table Browser UPDATE on implicit rowid table round-trips', () async {
      await conn.connect();
      await conn.execute('CREATE TABLE t (name TEXT)');
      await conn.execute("INSERT INTO t (name) VALUES ('Ada')");

      final schema = await conn.getTableSchema(table: 't');
      expect(schema.primaryKeys, isEmpty);

      final pks = sqliteTableBrowserPrimaryKeys(
        declaredPrimaryKeys: schema.primaryKeys,
        isView: false,
      );
      expect(pks, ['rowid']);
      expect(
        tableViewEditingEnabled(
          isView: false,
          customSqlActive: false,
          hasPrimaryKey: pks.isNotEmpty,
        ),
        isTrue,
      );
      expect(
        tableViewEditDisabledReason(
          isView: false,
          customSqlActive: false,
          hasPrimaryKey: pks.isNotEmpty,
          schemaLoaded: true,
        ),
        isNull,
      );

      final sql = sqliteBrowseDataSql(
        qualifiedFrom: SqliteConnection.quoteIdentifier('t'),
        primaryKeys: pks,
        isView: false,
        limit: 200,
        offset: 0,
      );
      final rs = await conn.execute(sql);
      expect(rs, isNotEmpty);
      final cols = rs.first.keys.toList();
      expect(cols, contains('rowid'));
      expect(cols, contains('name'));

      final rows = [
        for (final row in rs)
          [for (final c in cols) '${row[c]}'],
      ];
      final buffer = DataGridStagingBuffer(columns: cols, rows: rows);
      addTearDown(buffer.dispose);
      buffer.setCell(0, cols.indexOf('name'), 'Grace');

      final plan = buffer.generateMutationPlan(
        dialect: SqlDialect.sqlite,
        tableName: 't',
        primaryKeys: pks,
        columnDataTypes: {
          kSqliteImplicitRowid: 'INTEGER',
          'name': 'TEXT',
        },
        columnMeta: {kSqliteImplicitRowid: sqliteImplicitRowidColumn},
      );
      expect(plan.statements, hasLength(1));
      expect(plan.statements.first.sql, contains('WHERE "rowid" ='));

      expect(await conn.executeAffected(plan.statements.first.sql), 1);
      final after = await conn.execute('SELECT name FROM t');
      expect(after.first['name'], 'Grace');
    });

    test('WITHOUT ROWID tables keep the declared PK, not implicit rowid',
        () async {
      await conn.connect();
      await conn.execute(
        'CREATE TABLE wr (id INTEGER PRIMARY KEY, name TEXT) WITHOUT ROWID',
      );
      final schema = await conn.getTableSchema(table: 'wr');
      expect(schema.primaryKeys, ['id']);
      expect(
        sqliteTableBrowserPrimaryKeys(
          declaredPrimaryKeys: schema.primaryKeys,
          isView: false,
        ),
        ['id'],
      );
      expect(
        sqliteBrowseDataSql(
          qualifiedFrom: '"wr"',
          primaryKeys: schema.primaryKeys,
          isView: false,
          limit: 200,
          offset: 0,
        ),
        'SELECT * FROM "wr" ORDER BY "id" LIMIT 200 OFFSET 0',
      );
    });

    test('getObjectDdl returns CREATE SQL for a table that exists', () async {
      await conn.connect();
      await conn.execute(
        'CREATE TABLE foo (id INTEGER PRIMARY KEY, name TEXT)',
      );

      final ddl = await conn.getObjectDdl('foo');
      expect(ddl, isNot(contains('No definition found')));
      expect(ddl.toUpperCase(), contains('CREATE TABLE'));
      expect(ddl.toLowerCase(), contains('foo'));
    });

    test('executes INSERT, UPDATE, DELETE with RETURNING clause correctly',
        () async {
      await conn.connect();

      await conn.execute(
          'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');

      // INSERT with RETURNING
      final insertRes = await conn.execute(
          "INSERT INTO users (name) VALUES ('Alice') RETURNING id, name");
      expect(insertRes, isNotEmpty);
      expect(insertRes.first['id'], 1);
      expect(insertRes.first['name'], 'Alice');

      // UPDATE with RETURNING
      final updateRes = await conn.execute(
          "UPDATE users SET name = 'Bob' WHERE id = 1 RETURNING id, name");
      expect(updateRes, isNotEmpty);
      expect(updateRes.first['id'], 1);
      expect(updateRes.first['name'], 'Bob');

      // DELETE with RETURNING
      final deleteRes = await conn
          .execute("DELETE FROM users WHERE id = 1 RETURNING id, name");
      expect(deleteRes, isNotEmpty);
      expect(deleteRes.first['id'], 1);
      expect(deleteRes.first['name'], 'Bob');
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

    test('read-only rejects WITH INSERT; PRAGMA busy_timeout still allowed',
        () async {
      final roConn = SqliteConnection(
        id: 3,
        name: 'in_memory_ro_with',
        path: inMemoryDatabasePath,
        readOnly: true,
      );
      await roConn.connect();
      addTearDown(roConn.disconnect);

      expect(
        await roConn.execute('PRAGMA busy_timeout'),
        isNotEmpty,
      );
      expect(
        await roConn.execute('WITH x AS (SELECT 1) SELECT * FROM x'),
        isNotEmpty,
      );
      expect(
        () => roConn.execute(
          'WITH x AS (SELECT 1) INSERT INTO t SELECT * FROM x',
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => roConn.execute('PRAGMA journal_mode=WAL'),
        throwsA(isA<StateError>()),
      );
    });

    test('WITH INSERT on a writable connection applies DML', () async {
      await conn.connect();
      await conn.execute(
        'CREATE TABLE w (id INTEGER PRIMARY KEY, n INTEGER)',
      );
      await conn.execute(
        'WITH x AS (SELECT 7 AS n) INSERT INTO w (n) SELECT n FROM x',
      );
      final rows = await conn.execute('SELECT n FROM w');
      expect(rows, hasLength(1));
      expect(rows.first['n'], 7);
    });

    test('tracks BEGIN/COMMIT and refuses nested BEGIN via runInTransaction',
        () async {
      await conn.connect();
      await conn.execute(
        'CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)',
      );
      await conn.execute('BEGIN');
      expect(await conn.inOpenTransaction(), isTrue);

      await conn.runInTransaction(() async {
        await conn.execute("INSERT INTO t (name) VALUES ('a')");
      });
      expect(await conn.inOpenTransaction(), isTrue);
      await conn.execute('COMMIT');
      expect(await conn.inOpenTransaction(), isFalse);

      final rows = await conn.execute('SELECT COUNT(*) AS c FROM t');
      expect(rows.first['c'], 1);

      await conn.runInTransaction(() async {
        await conn.execute("INSERT INTO t (name) VALUES ('b')");
      });
      expect(await conn.inOpenTransaction(), isFalse);
      final rows2 = await conn.execute('SELECT COUNT(*) AS c FROM t');
      expect(rows2.first['c'], 2);
    });

    test('runInTransaction rolls back when a later statement fails', () async {
      await conn.connect();
      await conn.execute(
        'CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await conn.execute("INSERT INTO t (id, name) VALUES (1, 'keep')");

      await expectLater(
        conn.runInTransaction(() async {
          expectDmlMatchedRows(
            await conn.executeAffected(
              "UPDATE t SET name = 'changed' WHERE id = 1",
            ),
          );
          expectDmlMatchedRows(
            await conn.executeAffected(
              "UPDATE t SET name = 'ghost' WHERE id = 999",
            ),
          );
        }),
        throwsA(isA<StateError>()),
      );

      expect(await conn.inOpenTransaction(), isFalse);
      final rows = await conn.execute('SELECT id, name FROM t');
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'keep');
    });

    test('handles quotes in quoteIdentifier helper', () {
      expect(
          SqliteConnection.quoteIdentifier('normal_table'), '"normal_table"');
      expect(SqliteConnection.quoteIdentifier('table"with"quotes'),
          '"table""with""quotes"');
    });
  });

  group('SqliteConnection missing file (#798)', () {
    test('connect on a missing path does not create the file', () async {
      final dir = await Directory.systemTemp.createTemp('querya_sqlite_miss_');
      final path = '${dir.path}/oops.db';
      final conn = SqliteConnection(
        id: 1,
        name: 'missing',
        path: path,
      );
      addTearDown(() async {
        await conn.disconnect();
        await dir.delete(recursive: true);
      });

      await expectLater(
        conn.connect(),
        throwsA(
          isA<SqliteConnectionException>().having(
            (e) => e.message,
            'message',
            contains('not found'),
          ),
        ),
      );
      expect(File(path).existsSync(), isFalse);
      expect(conn.isConnected, isFalse);
    });

    test('testConnection on a missing path does not create the file', () async {
      final dir = await Directory.systemTemp.createTemp('querya_sqlite_test_');
      final path = '${dir.path}/oops.db';
      final conn = SqliteConnection(
        id: 1,
        name: 'missing',
        path: path,
      );
      addTearDown(() async {
        await conn.disconnect();
        await dir.delete(recursive: true);
      });

      final result = await conn.testConnection();
      expect(result.ok, isFalse);
      expect(result.error, contains('not found'));
      expect(File(path).existsSync(), isFalse);
    });

    test('createIfMissing creates an empty database', () async {
      final dir = await Directory.systemTemp.createTemp('querya_sqlite_new_');
      final path = '${dir.path}/new.db';
      addTearDown(() async {
        await dir.delete(recursive: true);
      });

      await SqliteConnection.createFileIfMissing(path);
      expect(File(path).existsSync(), isTrue);

      final conn = SqliteConnection(
        id: 1,
        name: 'created',
        path: path,
      );
      addTearDown(conn.disconnect);
      await conn.connect();
      expect(conn.isConnected, isTrue);
    });

    test('corrupt file is reported as not a database', () async {
      final dir = await Directory.systemTemp.createTemp('querya_sqlite_bad_');
      final path = '${dir.path}/junk.db';
      await File(path).writeAsString('this is not sqlite');
      final conn = SqliteConnection(
        id: 1,
        name: 'junk',
        path: path,
      );
      addTearDown(() async {
        await conn.disconnect();
        await dir.delete(recursive: true);
      });

      await expectLater(
        conn.connect(),
        throwsA(
          isA<SqliteConnectionException>().having(
            (e) => e.message.toLowerCase(),
            'message',
            anyOf(contains('corrupt'), contains('not a database')),
          ),
        ),
      );
      expect(conn.isConnected, isFalse);
    });

    test('sqliteMapOpenError distinguishes missing, permission, corrupt', () {
      expect(
        sqliteMapOpenError(StateError('file /x not found'), '/x').message,
        'SQLite file not found: /x',
      );
      expect(
        sqliteMapOpenError(
          Exception('OS Error: Permission denied, errno = 13'),
          '/x',
        ).message,
        'Permission denied opening SQLite file: /x',
      );
      expect(
        sqliteMapOpenError(
          Exception('file is not a database'),
          '/x',
        ).message,
        'SQLite database is corrupt or not a database: /x',
      );
    });
  });
}
