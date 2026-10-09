import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/mcp/mcp_access_store.dart';
import 'package:querya_desktop/core/mcp/mcp_query_service.dart';
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';

class _Access implements McpAccessPolicy {
  _Access(this.ids);
  final Set<int> ids;
  @override
  Future<bool> canRead(ConnectionRow row) async => ids.contains(row.id);
}

/// Answers catalog queries for a `users` / `orders` schema; records the rest.
class _Db extends FakeSqlExecutionDelegate {
  final limits = <int?>[];
  final timeouts = <Duration?>[];

  @override
  Future<SqlExecutionResult> executeQuery(String sql,
      {int? limit, Duration? timeout}) async {
    limits.add(limit);
    timeouts.add(timeout);
    return super.executeQuery(sql, limit: limit, timeout: timeout);
  }
}

const _secret = 'S3cret-Pw-77';

ConnectionRow _row(int id, String type, {String? env}) {
  final row = ConnectionRow(
    id: id,
    type: type,
    name: 'conn $id',
    host: type == 'sqlite' ? '/home/me/data/shop.db' : 'db.internal',
    port: 5432,
    username: 'admin',
    password: _secret,
    databaseName: type == 'sqlite' ? null : 'shop',
    connectionString: 'postgresql://admin:$_secret@db.internal/shop',
    createdAt: DateTime.utc(2026).toIso8601String(),
  );
  return env == null
      ? row
      : row.withEnvironment(ConnectionEnvironment.values
          .firstWhere((e) => e.storageValue == env));
}

SqlExecutionResult _catalog(String sql) {
  if (sql.contains('pg_indexes')) {
    return const SqlExecutionResult(columns: ['n', 'd'], rows: [
      ['users_pkey', 'CREATE UNIQUE INDEX users_pkey ON users (id)'],
    ]);
  }
  // PostgreSQL reads keys from pg_constraint (contype 'f'), MySQL and SQLite
  // from their own catalogs.
  if (sql.contains('FOREIGN KEY') || sql.contains("contype = 'f'")) {
    return const SqlExecutionResult(columns: ['t', 'c', 'rt', 'rc'], rows: [
      ['orders', 'user_id', 'users', 'id'],
    ]);
  }
  if (sql.contains('information_schema.columns') ||
      sql.contains('pg_attribute')) {
    return const SqlExecutionResult(columns: ['t', 'c', 'ty', 'pk'], rows: [
      ['users', 'id', 'integer', '1'],
      ['users', 'name', 'text', '0'],
      ['orders', 'id', 'integer', '1'],
      ['orders', 'user_id', 'integer', '0'],
    ]);
  }
  return const SqlExecutionResult(columns: ['n'], rows: [
    ['1'],
  ]);
}

void main() {
  late _Db db;
  late List<SqlDialect> dialects;
  late List<ConnectionRow> rows;

  McpQueryService service({Set<int> shared = const {1, 2, 3}, int maxCell = 4096}) =>
      McpQueryService(
        createDelegate: (row, dialect) {
          dialects.add(dialect);
          return db;
        },
        access: _Access(shared),
        loadConnections: () async => rows,
        maxCellChars: maxCell,
      );

  setUp(() {
    db = _Db()..onExecute = _catalog;
    dialects = [];
    rows = [
      _row(1, 'postgresql', env: 'production'),
      _row(2, 'mysql'),
      _row(3, 'sqlite'),
      _row(4, 'postgresql'), // not shared
      _row(5, 'mongodb'), // not SQL
    ];
  });

  group('listConnections', () {
    test('only shared SQL connections, without credentials', () async {
      final list = await service().listConnections();
      expect(list.map((c) => c.id), [1, 2, 3]);

      final json = jsonEncode([for (final c in list) c.toJson()]);
      for (final leak in [_secret, 'admin', 'db.internal', '/home/me', '5432']) {
        expect(json, isNot(contains(leak)), reason: leak);
      }
      expect(list.first.environment, 'production');
      expect(list.first.database, 'shop');
      expect(list.last.database, 'shop.db');
    });

    test('nothing is shared by default', () async {
      expect(await service(shared: {}).listConnections(), isEmpty);
    });
  });

  group('connection access', () {
    test('a connection that is not shared looks like a missing one', () async {
      final s = service();
      Future<String> msg(int id) async {
        try {
          await s.runQuery(id, 'SELECT 1');
        } on McpToolException catch (e) {
          return e.message.replaceAll('$id', '#');
        }
        fail('expected an error');
      }

      expect(await msg(4), await msg(99));
      expect(db.executed, isEmpty);
    });

    test('a non-SQL connection is refused', () async {
      await expectLater(service(shared: {5}).runQuery(5, 'SELECT 1'),
          throwsA(isA<McpToolException>()));
    });

    test('the dialect follows the connection type', () async {
      final s = service();
      await s.runQuery(1, 'SELECT 1');
      await s.runQuery(2, 'SELECT 1');
      await s.runQuery(3, 'SELECT 1');
      expect(dialects, [SqlDialect.postgres, SqlDialect.mysql, SqlDialect.sqlite]);
    });
  });

  group('runQuery', () {
    test('a refused statement never reaches the database', () async {
      await expectLater(service().runQuery(1, 'DELETE FROM users'),
          throwsA(isA<McpToolException>()));
      await expectLater(service().runQuery(1, 'SELECT 1; DROP TABLE users'),
          throwsA(isA<McpToolException>()));
      expect(db.executed, isEmpty);
    });

    test('runs with the row limit and the timeout and disposes the delegate',
        () async {
      final r = await service().runQuery(1, 'SELECT 1');
      expect(r.columns, ['n']);
      expect(r.rows, [
        ['1'],
      ]);
      expect(db.limits.single, 1000);
      expect(db.timeouts.single, const Duration(seconds: 15));
      expect(db.disposeCount, 1);
    });

    test('a capped result is reported as truncated', () async {
      db.onExecute = (_) => const SqlExecutionResult(
          columns: ['n'],
          rows: [
            ['1'],
          ],
          isTruncated: true);
      expect((await service().runQuery(1, 'SELECT 1')).truncated, isTrue);
    });

    test('long cells are cut with a marker', () async {
      db.onExecute = (_) => SqlExecutionResult(columns: const ['t'], rows: [
            ['x' * 50],
          ]);
      final r = await service(maxCell: 10).runQuery(1, 'SELECT t FROM x');
      expect(r.rows.single.single, '${'x' * 10}… [truncated 40 chars]');
    });

    test('database errors come back as tool errors', () async {
      db.onExecute = (_) => throw StateError('relation "nope" does not exist');
      await expectLater(service().runQuery(1, 'SELECT * FROM nope'),
          throwsA(isA<McpToolException>()));
      expect(db.disposeCount, 1);
    });

    test('a timeout becomes a readable error', () async {
      db.onExecute = (_) => throw TimeoutException('slow');
      await expectLater(
        service().runQuery(1, 'SELECT pg_sleep(60)'),
        throwsA(isA<McpToolException>().having(
            (e) => e.message, 'message', contains('time limit'))),
      );
    });
  });

  group('schema tools', () {
    test('listTables reports tables and column counts', () async {
      final tables = await service().listTables(1);
      expect([for (final t in tables) t.toJson()], [
        {'name': 'users', 'columns': 2},
        {'name': 'orders', 'columns': 2},
      ]);
    });

    test('describeTable has keys, references and indexes', () async {
      final users = await service().describeTable(1, 'users');
      expect(users.columns.first.primaryKey, isTrue);
      expect(users.indexes.single.name, 'users_pkey');

      final orders = await service().describeTable(1, 'ORDERS');
      expect(orders.name, 'orders');
      expect(orders.columns.last.references, 'users.id');
    });

    test('an unknown table is an error and runs no table query', () async {
      await expectLater(service().describeTable(1, 'users; DROP TABLE x'),
          throwsA(isA<McpToolException>()));
      expect(db.executed.where((s) => s.contains('DROP')), isEmpty);
    });

    test('sampleRows quotes the catalog name and clamps the count', () async {
      await service().sampleRows(2, 'users', rows: 5000);
      expect(db.executed.last, 'SELECT * FROM `users`');
      expect(db.limits.last, 100);

      await service().sampleRows(1, 'users', rows: 0);
      expect(db.executed.last, 'SELECT * FROM "users"');
      expect(db.limits.last, 1);
    });
  });

  group('explainQuery', () {
    test('explains a read and refuses a write', () async {
      db.explainPlan = 'Seq Scan on users';
      expect(await service().explainQuery(1, 'SELECT * FROM users;'),
          'Seq Scan on users');
      expect(db.explained, ['SELECT * FROM users']);

      await expectLater(service().explainQuery(1, 'DELETE FROM users'),
          throwsA(isA<McpToolException>()));
      await expectLater(service().explainQuery(1, 'EXPLAIN SELECT 1'),
          throwsA(isA<McpToolException>()));
      expect(db.explained, hasLength(1));
    });

    test('a driver without EXPLAIN says so', () async {
      db.explainSupported = false;
      await expectLater(service().explainQuery(1, 'SELECT 1'),
          throwsA(isA<McpToolException>()));
    });
  });
}
