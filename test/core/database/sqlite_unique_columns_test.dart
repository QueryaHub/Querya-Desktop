import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/database/sqlite_sql.dart';
import 'package:querya_desktop/core/mcp/mcp_access_store.dart';
import 'package:querya_desktop/core/mcp/mcp_query_service.dart';
import 'package:querya_desktop/core/mcp/mcp_sql_delegates.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _All implements McpAccessPolicy {
  @override
  Future<bool> canRead(ConnectionRow row) async => true;
}

void main() {
  group('sqliteUniqueColumnsSql', () {
    test('wraps a SELECT so repeated names get suffixes', () {
      expect(
        sqliteUniqueColumnsSql('SELECT o.id, u.id FROM o JOIN u ON 1'),
        'SELECT * FROM (\nSELECT o.id, u.id FROM o JOIN u ON 1\n)',
      );
    });

    test('wraps a WITH query, and leaves comments and semicolons outside', () {
      expect(
        sqliteUniqueColumnsSql('-- c\nWITH x AS (SELECT 1) SELECT * FROM x;  '),
        startsWith('SELECT * FROM (\n-- c\nWITH x AS (SELECT 1) SELECT * FROM x\n'),
      );
    });

    test('keeps a trailing line comment inside the parentheses', () {
      final wrapped = sqliteUniqueColumnsSql('SELECT 1, 1 -- note');
      expect(wrapped.endsWith('\n)'), isTrue);
    });

    test('leaves non-select statements and several statements unchanged', () {
      for (final sql in [
        'PRAGMA table_info(t)',
        'EXPLAIN QUERY PLAN SELECT 1',
        'VALUES (1, 1)',
        'UPDATE t SET a = 1',
        'SELECT 1; SELECT 2',
      ]) {
        expect(sqliteUniqueColumnsSql(sql), sql, reason: sql);
      }
    });
  });

  group('duplicate column names on a real SQLite file (#1144)', () {
    late Directory dir;
    late McpQueryService service;

    setUpAll(() async {
      sqfliteFfiInit();
      dir = await Directory.systemTemp.createTemp('querya_dup_cols_');
      final path = '${dir.path}/shop.db';
      final seed = SqliteConnection(
          id: 1, name: 'seed', path: path, createIfMissing: true);
      await seed.connect();
      await seed.execute(
          'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)');
      await seed.execute('CREATE TABLE orders (id INTEGER PRIMARY KEY, '
          'user_id INTEGER REFERENCES users(id), total REAL)');
      await seed.execute("INSERT INTO users VALUES (2, 'bob')");
      await seed.execute('INSERT INTO orders VALUES (12, 2, 9.5)');
      await seed.disconnect();

      service = McpQueryService(
        createDelegate: createReadOnlyMcpDelegate,
        access: _All(),
        loadConnections: () async => [
          ConnectionRow(
            id: 7,
            type: 'sqlite',
            name: 'Shop',
            host: path,
            createdAt: DateTime.utc(2026).toIso8601String(),
          ),
        ],
      );
    });

    tearDownAll(() async {
      await SqliteService.instance.disconnectAll();
      await dir.delete(recursive: true);
    });

    test('two id columns come back as two columns with their own values',
        () async {
      final r = await service.runQuery(7,
          'SELECT o.id, u.id FROM orders o JOIN users u ON u.id = o.user_id');
      expect(r.columns, ['id', 'id:1']);
      expect(r.rows.single, ['12', '2']);
    });

    test('SELECT 1, 1 keeps both columns', () async {
      final r = await service.runQuery(7, 'SELECT 1, 1');
      expect(r.columns, ['1', '1:1']);
      expect(r.rows.single, ['1', '1']);
    });

    test('o.*, u.* returns every column of both tables', () async {
      final r = await service.runQuery(7,
          'SELECT o.*, u.* FROM orders o LEFT JOIN users u ON u.id = o.user_id');
      expect(r.columns, ['id', 'user_id', 'total', 'id:1', 'name']);
      expect(r.rows.single, ['12', '2', '9.5', '2', 'bob']);
    });

    test('a WITH query with a repeated name is unchanged in its values',
        () async {
      final r = await service.runQuery(7,
          'WITH x AS (SELECT id FROM users) SELECT x.id, u.id FROM x JOIN users u ON u.id = x.id -- done');
      expect(r.columns, ['id', 'id:1']);
      expect(r.rows.single, ['2', '2']);
    });

    test('results with unique names keep their names and order', () async {
      final r = await service.runQuery(7, 'SELECT name, id FROM users ORDER BY id');
      expect(r.columns, ['name', 'id']);
      expect(r.rows, [
        ['bob', '2'],
      ]);
    });
  });
}
