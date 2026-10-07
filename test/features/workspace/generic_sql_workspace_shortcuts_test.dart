import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/generic_sql_workspace.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show OutlineButton;

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/local_db_test_support.dart';
import '../../support/querya_theme_test_shell.dart';

const _connectionId = 7002;

/// A hung test must fail in a minute instead of blocking CI for ten.
const _timeout = Timeout(Duration(seconds: 60));

const _connection = ConnectionRow(
  id: _connectionId,
  type: 'sqlite',
  name: 'Synthetic',
  host: '/tmp/synthetic.db',
  createdAt: '2026-01-01T00:00:00Z',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async => tempDir = await initTestLocalDb('generic_ws_keys_'));
  tearDownAll(() => disposeTestLocalDb(tempDir));

  tearDown(() {
    SqlEditorCommandBridge.instance.unregister(connectionId: _connectionId);
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
            connectionRow: _connection,
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

  /// Lets the real async work behind `execute` (SQLite settings reads) finish.
  /// The action itself runs in the test zone; each round gives real time to
  /// the pending I/O and then pumps so the continuation (a fake-async
  /// microtask) runs and can start the next step.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the Execute button runs the active tab and shows the result', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'SELECT n FROM t',
    );

    await tester.tap(find.widgetWithText(OutlineButton, 'Execute (F5)'));
    await settle(tester);

    expect(delegate.executed, ['SELECT n FROM t']);
    expect(state.activeSession.columns, ['n']);
    expect(state.activeSession.rows, [
      ['1'],
    ]);
    expect(state.activeSession.statusLine, startsWith('1 row(s).'));
    expect(state.activeSession.running, isFalse);
  });

  testWidgets('F5 executes the active tab', timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    await pumpWorkspace(tester, delegate, initialSql: 'SELECT 1');

    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await settle(tester);

    expect(delegate.executed, ['SELECT 1']);
  });

  testWidgets('Ctrl+Enter executes the active tab', timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    await pumpWorkspace(tester, delegate, initialSql: 'SELECT 2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(delegate.executed, ['SELECT 2']);
  });

  testWidgets('Ctrl+T opens a tab and Ctrl+W closes it', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Query 2'), findsNothing);
    expect(state.activeSession.title, 'Query 1');
  });

  testWidgets('Ctrl+Tab and Ctrl+Shift+Tab cycle through the tabs', timeout: _timeout,
      (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());
    state.addNewTab();
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 1');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 2');
  });

  testWidgets('blank SQL is not sent to the database', timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    final state = await pumpWorkspace(tester, delegate, initialSql: '   ');

    unawaited(state.execute());
    await settle(tester);

    expect(delegate.executed, isEmpty);
  });

  // Disabled: this test hung CI for the full 10-minute timeout. Selecting
  // text by assigning the controller value does not mimic a user selection in
  // the editor. Re-enable once the selection is made through the mounted
  // editor (EditableTextState.userUpdateTextEditingValue).
  testWidgets('only the selected text runs when there is a selection', timeout: _timeout,
      skip: true,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    final state = await pumpWorkspace(tester, delegate);
    const sql = 'SELECT 1; SELECT 2';
    state.activeSession.controller.value = const TextEditingValue(
      text: sql,
      selection: TextSelection(baseOffset: 10, extentOffset: 18),
    );

    unawaited(state.execute());
    await settle(tester);

    expect(delegate.executed, ['SELECT 2']);
  });

  testWidgets('a second execute is ignored while a query is running', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate()..gate = Completer<void>();
    final state = await pumpWorkspace(tester, delegate, initialSql: 'SELECT 1');

    unawaited(state.execute());
    await settle(tester);
    expect(state.activeSession.running, isTrue);

    unawaited(state.execute());
    await tester.pump();
    expect(delegate.executed, ['SELECT 1']);

    delegate.gate!.complete();
    await settle(tester);
    expect(state.activeSession.running, isFalse);
    expect(delegate.executed, ['SELECT 1']);
  });

  testWidgets('a failing query shows its error and clears the running state', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate(
      onExecute: (_) => throw Exception('syntax error near FORM'),
    );
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'SELECT * FORM t',
    );

    unawaited(state.execute());
    await settle(tester);

    expect(state.activeSession.error, contains('syntax error near FORM'));
    expect(state.activeSession.running, isFalse);
  });

  testWidgets('a statement that returns no rows reports the affected count', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate(
      onExecute: (_) => const SqlExecutionResult(affectedRows: 3),
    );
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'UPDATE t SET a = 1 WHERE b = 2',
    );

    unawaited(state.execute());
    await settle(tester);

    expect(state.activeSession.statusLine, 'OK. Rows affected: 3.');
    expect(state.activeSession.affectedRows, 3);
  });

  testWidgets('the format command upper-cases SQL keywords', timeout: _timeout, (tester) async {
    await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'select id from users',
    );

    SqlEditorCommandBridge.instance.invokeFormat();
    await tester.pumpAndSettle();

    final state = tester.state<GenericSqlWorkspaceState>(
      find.byType(GenericSqlWorkspace),
    );
    expect(state.activeSession.controller.text, 'SELECT id FROM users');
  });

  testWidgets('the clear command empties the editor', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'SELECT 1',
    );

    SqlEditorCommandBridge.instance.invokeClear();
    await tester.pumpAndSettle();

    expect(state.activeSession.controller.text, isEmpty);
  });
}
