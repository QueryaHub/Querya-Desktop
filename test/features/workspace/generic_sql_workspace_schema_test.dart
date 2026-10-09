import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/generic_sql_workspace.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:querya_desktop/features/workspace/sql_result_grid_schema.dart';

import '../../memory_secrets_backend.dart';
import '../../support/fake_sql_execution_delegate.dart';
import '../../support/local_db_test_support.dart';
import '../../support/querya_theme_test_shell.dart';

/// Answers queries normally, but the table schema never arrives unless
/// [schemaAnswer] completes it, and every lookup is counted.
class _SchemaDelegate extends FakeSqlExecutionDelegate {
  _SchemaDelegate({this.hang = false})
      : super(
          onExecute: (sql) => const SqlExecutionResult(
            columns: ['id', 'name'],
            rows: [
              ['1', 'Alice'],
            ],
          ),
        );

  final bool hang;
  final lookups = <String>[];

  @override
  Future<SqlResultGridSchema> resolveTableSchema(
    String userSql,
    List<String> columns,
  ) {
    lookups.add(userSql);
    if (hang) return Completer<SqlResultGridSchema>().future;
    return Future.value(SqlResultGridSchema.none);
  }
}

/// Counts the transaction probes the workspace sends to the server.
class _TxDelegate extends FakeSqlExecutionDelegate {
  _TxDelegate()
      : super(
          onExecute: (sql) => const SqlExecutionResult(
            columns: ['id'],
            rows: [
              ['1'],
            ],
          ),
        );

  var probes = 0;

  @override
  bool get supportsTransactions => true;

  @override
  Future<bool?> checkTransactionOpen() async {
    probes++;
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late int connectionId;
  late ConnectionRow connection;

  setUpAll(() async => tempDir = await initTestLocalDb('generic_ws_schema_'));
  tearDownAll(() => disposeTestLocalDb(tempDir));

  setUp(() async {
    connectionId = await LocalDb.instance.addConnection(
      const ConnectionRow(
        type: 'sqlite',
        name: 'Schema DB',
        host: '/tmp/schema.db',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );
    connection = ConnectionRow(
      id: connectionId,
      type: 'sqlite',
      name: 'Schema DB',
      host: '/tmp/schema.db',
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
    FakeSqlExecutionDelegate delegate,
    String initialSql,
  ) async {
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox.expand(
          child: GenericSqlWorkspace(
            connectionRow: connection,
            delegate: delegate,
            dialect: SqlDialect.sqlite,
            initialSql: initialSql,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<GenericSqlWorkspaceState>(
      find.byType(GenericSqlWorkspace),
    );
  }

  Future<void> runAndWait(
    WidgetTester tester,
    GenericSqlWorkspaceState state,
  ) async {
    unawaited(state.execute());
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
  }

  testWidgets('rows show while the table schema lookup never completes',
      (tester) async {
    final delegate = _SchemaDelegate(hang: true);
    final state = await pumpWorkspace(tester, delegate, 'select * from users');
    await runAndWait(tester, state);

    expect(delegate.lookups, ['select * from users']);
    expect(find.text('Alice'), findsWidgets);
  });

  testWidgets('the same query is not looked up again', (tester) async {
    final delegate = _SchemaDelegate();
    final state = await pumpWorkspace(tester, delegate, 'select * from users');
    await runAndWait(tester, state);
    await runAndWait(tester, state);
    expect(delegate.lookups.length, 1);
  });

  testWidgets('a plain read in autocommit does not probe the transaction again',
      (tester) async {
    final delegate = _TxDelegate();
    final state = await pumpWorkspace(tester, delegate, 'select 1');
    await runAndWait(tester, state);
    expect(delegate.probes, 1);
    await runAndWait(tester, state);
    expect(delegate.probes, 1);
  });
}
