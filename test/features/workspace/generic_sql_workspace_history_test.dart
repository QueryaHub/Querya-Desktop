import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/generic_sql_workspace.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../memory_secrets_backend.dart';
import '../../support/fake_sql_execution_delegate.dart';
import '../../support/local_db_test_support.dart';
import '../../support/querya_theme_test_shell.dart';

/// A hung test must fail in a minute instead of blocking CI for ten.
const _timeout = Timeout(Duration(seconds: 60));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late int connectionId;
  late ConnectionRow connection;

  setUpAll(() async => tempDir = await initTestLocalDb('generic_ws_history_'));
  tearDownAll(() => disposeTestLocalDb(tempDir));

  setUp(() async {
    // Runs in the real zone (plain setUp of a testWidgets group is fine for
    // I/O because it is not inside the fake-async test body).
    await LocalDb.instance.clearMutationAudit();
    connectionId = await LocalDb.instance.addConnection(
      const ConnectionRow(
        type: 'sqlite',
        name: 'History DB',
        host: '/tmp/history.db',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );
    connection = ConnectionRow(
      id: connectionId,
      type: 'sqlite',
      name: 'History DB',
      host: '/tmp/history.db',
      createdAt: '2026-01-01T00:00:00Z',
    );
  });

  tearDown(() async {
    SqlEditorCommandBridge.instance.unregister(connectionId: connectionId);
    testMemorySecrets.clear();
    for (final c in await LocalDb.instance.getConnections()) {
      if (c.id != null) await LocalDb.instance.removeConnection(c.id!);
    }
  });

  Future<GenericSqlWorkspaceState> pumpWorkspace(
    WidgetTester tester,
    FakeSqlExecutionDelegate delegate, {
    required String initialSql,
    ConnectionRow? row,
    String Function()? effectiveDatabaseName,
  }) async {
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox.expand(
          child: GenericSqlWorkspace(
            connectionRow: row ?? connection,
            delegate: delegate,
            dialect: SqlDialect.sqlite,
            initialSql: initialSql,
            effectiveDatabaseName: effectiveDatabaseName,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<GenericSqlWorkspaceState>(
      find.byType(GenericSqlWorkspace),
    );
  }

  Future<void> run(WidgetTester tester, GenericSqlWorkspaceState state) async {
    unawaited(state.execute());
    // Settings are read, then history and audit rows are written without being
    // awaited: every hop needs real time and a pump so its continuation runs.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<List<SqlQueryHistoryEntry>> history(
    WidgetTester tester, {
    String? databaseName,
  }) async =>
      (await tester.runAsync(
        () => LocalDb.instance.listSqlQueryHistory(
          connectionId: connectionId,
          databaseName: databaseName,
        ),
      ))!;

  Future<List<MutationAuditEntry>> audit(WidgetTester tester) async =>
      (await tester.runAsync(LocalDb.instance.listMutationAudit))!;

  testWidgets('an executed query is written to the SQL history', timeout: _timeout,
      (tester) async {
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'SELECT n FROM t',
    );

    await run(tester, state);

    final entries = await history(tester);
    expect(entries.map((e) => e.sqlText), ['SELECT n FROM t']);
  });

  testWidgets('history is bucketed by the effective database name', timeout: _timeout,
      (tester) async {
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'SELECT 1',
      effectiveDatabaseName: () => 'analytics',
    );

    await run(tester, state);

    expect((await history(tester, databaseName: 'analytics')).single.sqlText,
        'SELECT 1');
    expect(await history(tester), isEmpty);
  });

  testWidgets('repeated runs are recorded newest first', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'SELECT 1',
    );
    await run(tester, state);
    state.activeSession.controller.text = 'SELECT 2';
    await run(tester, state);

    final entries = await history(tester);
    expect(entries.map((e) => e.sqlText), ['SELECT 2', 'SELECT 1']);
  });

  testWidgets('a failed query is not written to the history', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(onExecute: (_) => throw Exception('boom')),
      initialSql: 'SELECT broken',
    );

    await run(tester, state);

    expect(state.activeSession.error, contains('boom'));
    expect(await history(tester), isEmpty);
  });

  testWidgets('a SELECT is not written to the mutation audit trail', timeout: _timeout,
      (tester) async {
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'SELECT 1',
    );

    await run(tester, state);

    expect(await audit(tester), isEmpty);
  });

  testWidgets('an UPDATE is audited with rows affected and the environment', timeout: _timeout,
      (tester) async {
    final prod = connection.withEnvironment(ConnectionEnvironment.production);
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(
        onExecute: (_) => const SqlExecutionResult(affectedRows: 4),
      ),
      initialSql: 'UPDATE orders SET paid = 1 WHERE day = 2',
      row: prod,
      effectiveDatabaseName: () => 'shop',
    );

    await run(tester, state);

    final entries = await audit(tester);
    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.sqlText, 'UPDATE orders SET paid = 1 WHERE day = 2');
    expect(entry.rowsAffected, 4);
    expect(entry.environment, 'production');
    expect(entry.databaseName, 'shop');
    expect(entry.connectionName, 'History DB');
    expect(entry.source, MutationAuditSource.sqlEditor);
  });
}
