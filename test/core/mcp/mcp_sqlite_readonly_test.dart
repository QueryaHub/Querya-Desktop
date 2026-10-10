import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/mcp/mcp_access_store.dart';
import 'package:querya_desktop/core/mcp/mcp_query_service.dart';
import 'package:querya_desktop/app/mcp_sql_delegates.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _All implements McpAccessPolicy {
  @override
  Future<bool> canRead(ConnectionRow row) async => true;
}

/// The real SQLite path: the MCP delegate opens the file read-only, so even a
/// write that slipped past the guard is refused by the database.
void main() {
  late Directory dir;
  late ConnectionRow row;
  late McpQueryService service;

  setUpAll(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('querya_mcp_sqlite_');
    final path = '${dir.path}/shop.db';
    final seed = SqliteConnection(
        id: 1, name: 'seed', path: path, createIfMissing: true);
    await seed.connect();
    await seed.execute(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)');
    await seed.execute('CREATE TABLE orders (id INTEGER PRIMARY KEY, '
        'user_id INTEGER REFERENCES users(id), total REAL)');
    await seed.execute('CREATE INDEX orders_user ON orders (user_id)');
    await seed.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY, '
        "email TEXT UNIQUE, status TEXT DEFAULT 'new')");
    await seed.execute("INSERT INTO users VALUES (1, 'ann'), (2, 'bob')");
    await seed.execute('INSERT INTO orders VALUES (1, 1, 9.5)');
    await seed.disconnect();

    row = ConnectionRow(
      id: 42,
      type: 'sqlite',
      name: 'Shop',
      host: path,
      createdAt: DateTime.utc(2026).toIso8601String(),
    );
    service = McpQueryService(
      createDelegate: createReadOnlyMcpDelegate,
      access: _All(),
      loadConnections: () async => [row],
    );
  });

  tearDownAll(() async {
    await SqliteService.instance.disconnectAll();
    await dir.delete(recursive: true);
  });

  test('schema, samples and queries work on a read-only session', () async {
    final tables = await service.listTables(42);
    expect(tables.map((t) => t.name), containsAll(['users', 'orders']));

    final orders = await service.describeTable(42, 'orders');
    expect(orders.columns.firstWhere((c) => c.name == 'user_id').references,
        'users.id');
    expect(orders.indexes.map((i) => i.name), contains('orders_user'));

    final sample = await service.sampleRows(42, 'users', rows: 1);
    expect(sample.rows, hasLength(1));

    final r = await service.runQuery(42,
        'SELECT u.name, o.total FROM users u JOIN orders o ON o.user_id = u.id');
    expect(r.rows.single, ['ann', '9.5']);

    final plan = await service.explainQuery(42, 'SELECT * FROM orders WHERE user_id = 1');
    expect(plan, isNotEmpty);
  });

  test('the real SQLite catalog reports unique, default and identity (#1277)',
      () async {
    final accounts = await service.describeTable(42, 'accounts');
    final c = {for (final c in accounts.columns) c.name: c};
    expect(c['id']!.identity, isTrue, reason: 'INTEGER PRIMARY KEY');
    expect(c['email']!.unique, isTrue);
    expect(c['email']!.defaultValue, isNull);
    expect(c['status']!.defaultValue, "'new'");
    expect(c['status']!.unique, isFalse);
  });

  test('the database itself refuses a write on the MCP session', () async {
    final delegate = createReadOnlyMcpDelegate(row, SqlDialect.sqlite);
    addTearDown(delegate.dispose);
    await expectLater(
      delegate.executeQuery("INSERT INTO users VALUES (3, 'eve')"),
      throwsA(anything),
    );
    final check = await service.runQuery(42, 'SELECT COUNT(*) FROM users');
    expect(check.rows.single.single, '2');
  });
}
