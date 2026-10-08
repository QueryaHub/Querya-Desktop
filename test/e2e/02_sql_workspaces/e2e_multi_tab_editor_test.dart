import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/features/workspace/generic_sql_workspace.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../helpers/e2e_app_harness.dart';
import '../helpers/e2e_sql_workspace_helper.dart';

const _timeout = Timeout(Duration(seconds: 60));

void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_tabs_');
  late E2eSqlWorkspace ws;
  setUpAll(() async {
    await app.setUpAll();
    ws = await E2eSqlWorkspace.create();
  });
  tearDownAll(app.tearDownAll);
  tearDown(() => SqlEditorCommandBridge.instance
      .unregister(connectionId: ws.connection.id));

  testWidgets('each tab keeps its own SQL and result', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate(
      onExecute: (sql) => SqlExecutionResult(
        columns: const ['q'],
        rows: [
          [sql],
        ],
      ),
    );
    final state = await ws.pump(tester, delegate, initialSql: 'SELECT 1');

    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.enter);
    await E2eSqlWorkspace.settle(tester);
    expect(state.activeSession.rows, [
      ['SELECT 1'],
    ]);

    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.keyT);
    expect(state.activeSession.title, 'Query 2');
    expect(state.activeSession.rows, isEmpty);

    state.activeSession.controller.text = 'SELECT 2';
    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.enter);
    await E2eSqlWorkspace.settle(tester);
    expect(delegate.executed, ['SELECT 1', 'SELECT 2']);
    expect(state.activeSession.rows, [
      ['SELECT 2'],
    ]);

    // Back to the first tab: its result is untouched.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.activeSession.title, 'Query 1');
    expect(state.activeSession.rows, [
      ['SELECT 1'],
    ]);
  });

  testWidgets('closing a tab with unsaved text asks first', timeout: _timeout,
      (tester) async {
    final state = await ws.pump(tester, FakeSqlExecutionDelegate());
    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.keyT);
    state.activeSession.controller.text = 'DELETE FROM t';
    await tester.pump();

    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.keyW);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('discard'), findsWidgets);
    expect(state.activeSession.title, 'Query 2');
    expect(find.byType(GenericSqlWorkspace), findsOneWidget);
  });
}
