@Timeout(Duration(seconds: 60))
library;

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

  /// Runs [action] outside the fake-async zone (query execution reads its
  /// settings from the real SQLite file) and lets the work finish.
  Future<void> real(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      await action();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  testWidgets('the Execute button runs the active tab and shows the result',
      (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'SELECT n FROM t',
    );

    await real(tester, () async {
      await tester.tap(find.widgetWithText(OutlineButton, 'Execute (F5)'));
    });

    expect(delegate.executed, ['SELECT n FROM t']);
    expect(state.activeSession.columns, ['n']);
    expect(state.activeSession.rows, [
      ['1'],
    ]);
    expect(state.activeSession.statusLine, startsWith('1 row(s).'));
    expect(state.activeSession.running, isFalse);
  });

  testWidgets('F5 executes the active tab', (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    await pumpWorkspace(tester, delegate, initialSql: 'SELECT 1');

    await real(tester, () => tester.sendKeyEvent(LogicalKeyboardKey.f5));

    expect(delegate.executed, ['SELECT 1']);
  });

  testWidgets('Ctrl+Enter executes the active tab', (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    await pumpWorkspace(tester, delegate, initialSql: 'SELECT 2');

    await real(tester, () async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    expect(delegate.executed, ['SELECT 2']);
  });

  testWidgets('Ctrl+T opens a tab and Ctrl+W closes it', (tester) async {
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

  testWidgets('Ctrl+Tab and Ctrl+Shift+Tab cycle through the tabs',
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

  testWidgets('blank SQL is not sent to the database', (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    final state = await pumpWorkspace(tester, delegate, initialSql: '   ');

    await real(tester, () => state.execute());

    expect(delegate.executed, isEmpty);
  });

  // Disabled: this test hung CI for the full 10-minute timeout. Selecting
  // text by assigning the controller value does not mimic a user selection in
  // the editor. Re-enable once the selection is made through the mounted
  // editor (EditableTextState.userUpdateTextEditingValue).
  testWidgets('only the selected text runs when there is a selection',
      skip: true,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    final state = await pumpWorkspace(tester, delegate);
    const sql = 'SELECT 1; SELECT 2';
    state.activeSession.controller.value = const TextEditingValue(
      text: sql,
      selection: TextSelection(baseOffset: 10, extentOffset: 18),
    );

    await real(tester, () => state.execute());

    expect(delegate.executed, ['SELECT 2']);
  });

  testWidgets('a second execute is ignored while a query is running',
      (tester) async {
    final delegate = FakeSqlExecutionDelegate()..gate = Completer<void>();
    final state = await pumpWorkspace(tester, delegate, initialSql: 'SELECT 1');

    await real(tester, () async {
      unawaited(state.execute());
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await state.execute();
    });
    expect(state.activeSession.running, isTrue);
    expect(delegate.executed, ['SELECT 1']);

    await real(tester, () async => delegate.gate!.complete());
    expect(state.activeSession.running, isFalse);
  });

  testWidgets('a failing query shows its error and clears the running state',
      (tester) async {
    final delegate = FakeSqlExecutionDelegate(
      onExecute: (_) => throw Exception('syntax error near FORM'),
    );
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'SELECT * FORM t',
    );

    await real(tester, () => state.execute());

    expect(state.activeSession.error, contains('syntax error near FORM'));
    expect(state.activeSession.running, isFalse);
  });

  testWidgets('a statement that returns no rows reports the affected count',
      (tester) async {
    final delegate = FakeSqlExecutionDelegate(
      onExecute: (_) => const SqlExecutionResult(affectedRows: 3),
    );
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'UPDATE t SET a = 1 WHERE b = 2',
    );

    await real(tester, () => state.execute());

    expect(state.activeSession.statusLine, 'OK. Rows affected: 3.');
    expect(state.activeSession.affectedRows, 3);
  });

  testWidgets('the format command upper-cases SQL keywords', (tester) async {
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

  testWidgets('the clear command empties the editor', (tester) async {
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
