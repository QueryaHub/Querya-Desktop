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

const _connectionId = 7001;

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

  setUpAll(() async => tempDir = await initTestLocalDb('generic_ws_sessions_'));
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

  testWidgets('starts with one tab holding the initial SQL', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'SELECT 1',
    );

    expect(find.text('Query 1'), findsOneWidget);
    expect(state.activeSession.title, 'Query 1');
    expect(state.activeSession.controller.text, 'SELECT 1');
  });

  testWidgets('addNewTab appends a tab and activates it', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());

    state.addNewTab();
    await tester.pumpAndSettle();

    expect(find.text('Query 1'), findsOneWidget);
    expect(find.text('Query 2'), findsOneWidget);
    expect(state.activeSession.title, 'Query 2');
  });

  testWidgets('new tabs can carry SQL and a title', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());

    state.addNewTab(initialSql: 'SELECT 2', title: 'Report');
    await tester.pumpAndSettle();

    expect(state.activeSession.title, 'Report');
    expect(state.activeSession.controller.text, 'SELECT 2');
  });

  testWidgets('nextTab and prevTab wrap around the tab list', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());
    state.addNewTab();
    state.addNewTab();
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 3');

    state.nextTab();
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 1');

    state.prevTab();
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 3');

    state.prevTab();
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 2');
  });

  testWidgets('selecting a tab in the tab bar switches the active session', timeout: _timeout,
      (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());
    state.addNewTab();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Query 1'));
    await tester.pumpAndSettle();

    expect(state.activeSession.title, 'Query 1');
  });

  testWidgets('the last remaining tab cannot be closed', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());

    await state.closeTab(0);
    await tester.pumpAndSettle();

    expect(find.text('Query 1'), findsOneWidget);
    expect(state.activeSession.title, 'Query 1');
  });

  testWidgets('closing a clean tab removes it and keeps a valid active tab', timeout: _timeout,
      (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());
    state.addNewTab();
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 2');

    await state.closeTab(1);
    await tester.pumpAndSettle();

    expect(find.text('Query 2'), findsNothing);
    expect(state.activeSession.title, 'Query 1');
  });

  testWidgets('closing a dirty tab asks first; Cancel keeps it', timeout: _timeout,
      (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());
    state.addNewTab();
    await tester.pumpAndSettle();
    state.activeSession.controller.text = 'SELECT 42';
    expect(state.activeSession.isDirty, isTrue);

    final closing = state.closeTab(1);
    await tester.pumpAndSettle();
    expect(find.text('Unsaved Changes in "Query 2"'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await closing;

    expect(find.text('Query 2'), findsOneWidget);
    expect(state.activeSession.controller.text, 'SELECT 42');
  });

  testWidgets('closing a dirty tab with Discard & Close removes it', timeout: _timeout,
      (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());
    state.addNewTab();
    await tester.pumpAndSettle();
    state.activeSession.controller.text = 'SELECT 42';

    final closing = state.closeTab(1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard & Close'));
    await tester.pumpAndSettle();
    await closing;

    expect(find.text('Query 2'), findsNothing);
    expect(state.activeSession.title, 'Query 1');
  });

  testWidgets('tabs keep their own SQL text when switching', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'SELECT first',
    );
    state.addNewTab(initialSql: 'SELECT second');
    await tester.pumpAndSettle();

    state.prevTab();
    await tester.pumpAndSettle();
    expect(state.activeSession.controller.text, 'SELECT first');

    state.nextTab();
    await tester.pumpAndSettle();
    expect(state.activeSession.controller.text, 'SELECT second');
  });

  testWidgets('disposing the workspace disposes the delegate', timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    await pumpWorkspace(tester, delegate);

    await tester.pumpWidget(
      queryaThemeTestShell(child: const material.SizedBox.shrink()),
    );
    await tester.pumpAndSettle();

    expect(delegate.disposeCount, 1);
  });

  testWidgets('disposing while a query runs cancels it', timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate()..gate = Completer<void>();
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'SELECT slow',
    );

    // Settings are read from the real SQLite file: start the query in the test
    // zone, then let real time pass so it reaches the (blocked) delegate.
    unawaited(state.execute());
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
    }
    expect(state.activeSession.running, isTrue);
    expect(delegate.executed, ['SELECT slow']);

    await tester.pumpWidget(
      queryaThemeTestShell(child: const material.SizedBox.shrink()),
    );
    await tester.pump();
    expect(delegate.cancelCount, 1);

    delegate.gate!.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });
}
