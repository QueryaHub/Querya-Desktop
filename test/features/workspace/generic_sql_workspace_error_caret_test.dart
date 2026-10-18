import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/generic_sql_workspace.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/local_db_test_support.dart';
import '../../support/querya_theme_test_shell.dart';


/// A hung test must fail in a minute instead of blocking CI for ten.
const _timeout = Timeout(Duration(seconds: 60));


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ConnectionRow connection;

  setUpAll(() async {
    tempDir = await initTestLocalDb('generic_ws_error_caret_');
    // History is written with a foreign key to `connections`, so the workspace
    // needs a connection that really exists.
    const row = ConnectionRow(
      type: 'sqlite',
      name: 'Synthetic',
      host: '/tmp/synthetic.db',
      createdAt: '2026-01-01T00:00:00Z',
    );
    final id = await LocalDb.instance.addConnection(row);
    connection = row.copyWith(id: id);
  });
  tearDownAll(() => disposeTestLocalDb(tempDir));

  tearDown(() {
    SqlEditorCommandBridge.instance.unregister(connectionId: connection.id);
  });

  Future<GenericSqlWorkspaceState> pumpWorkspace(
    WidgetTester tester,
    FakeSqlExecutionDelegate delegate, {
    String? initialSql,
  }) async {
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

  /// What SQLite throws for a bad column in a query the app wrapped (#1144),
  /// with [at] counting bytes from the start of the wrapper.
  Object sqliteError(String sql, int at) => Exception(
        'SqliteFfiException(sqlite_error: 1, , SqliteException(1): while '
        'preparing statement, no such column: nope, SQL logic error (code 1)\n'
        '  Causing statement (at position $at): SELECT * FROM (\n$sql\n)\n'
        'LIMIT 5000})',
      );

  Future<void> run(
    WidgetTester tester,
    GenericSqlWorkspaceState state,
  ) async {
    // Settings are read from the real SQLite file: start the query in the test
    // zone, then let real time pass.
    unawaited(state.execute());
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
    }
  }

  testWidgets('a failed query puts the caret where the driver says',
      timeout: _timeout, (tester) async {
    const sql = 'SELECT a,\n  nope\nFROM t';
    final delegate = FakeSqlExecutionDelegate(onExecute: (s) {
      throw sqliteError(s, 16 + sql.indexOf('nope'));
    });
    final state = await pumpWorkspace(tester, delegate, initialSql: sql);

    await run(tester, state);

    final session = state.activeSession;
    expect(session.error, contains('no such column: nope'));
    expect(session.controller.selection.isCollapsed, isTrue);
    expect(session.controller.selection.baseOffset, sql.indexOf('nope'));
  });

  testWidgets('leading blank lines in the editor are counted',
      timeout: _timeout, (tester) async {
    const sql = 'SELECT nope FROM t';
    const padded = '\n\n  $sql';
    final delegate = FakeSqlExecutionDelegate(onExecute: (s) {
      throw sqliteError(s, 16 + sql.indexOf('nope'));
    });
    final state = await pumpWorkspace(tester, delegate, initialSql: padded);

    await run(tester, state);

    expect(state.activeSession.controller.selection.baseOffset,
        padded.indexOf('nope'));
  });

  testWidgets('an error without a position leaves the caret alone',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate(
      onExecute: (s) =>
          throw Exception('MySQLServerException [1064]: You have an error'),
    );
    final state = await pumpWorkspace(tester, delegate, initialSql: 'SELEC 1');
    state.activeSession.controller.selection =
        const material.TextSelection.collapsed(offset: 2);

    await run(tester, state);

    expect(state.activeSession.error, contains('1064'));
    expect(state.activeSession.controller.selection.baseOffset, 2);
  });
}
