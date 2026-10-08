import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../helpers/e2e_app_harness.dart';
import '../helpers/e2e_sql_workspace_helper.dart';

const _timeout = Timeout(Duration(seconds: 60));

void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_explain_');
  late E2eSqlWorkspace ws;
  setUpAll(() async {
    await app.setUpAll();
    ws = await E2eSqlWorkspace.create();
  });
  tearDownAll(app.tearDownAll);

  testWidgets('Explain shows the plan line by line without running the query',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate()
      ..explainPlan = 'Seq Scan on users\n  Filter: (id > 1)\n';
    await ws.pump(tester, delegate, initialSql: 'SELECT * FROM users');

    await tester.tap(find.text('Explain'));
    await E2eSqlWorkspace.settle(tester);

    expect(delegate.explained, ['SELECT * FROM users']);
    expect(delegate.executed, isEmpty);
    expect(find.text('QUERY PLAN'), findsWidgets);
    expect(find.text('Seq Scan on users'), findsOneWidget);
    expect(find.textContaining('Filter: (id > 1)'), findsOneWidget);
    expect(find.text('Query plan: 2 line(s).'), findsOneWidget);
  });

  testWidgets('Explain with an empty editor does nothing',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    await ws.pump(tester, delegate);

    await tester.tap(find.text('Explain'));
    await E2eSqlWorkspace.settle(tester);

    expect(delegate.explained, isEmpty);
  });

  testWidgets('a failing Explain reports the error',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate()
      ..explainError = StateError('syntax error at or near "SELEC"');
    await ws.pump(tester, delegate, initialSql: 'SELEC 1');

    await tester.tap(find.text('Explain'));
    await E2eSqlWorkspace.settle(tester);

    expect(find.textContaining('syntax error at or near'), findsWidgets);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('Cancel appears while a query runs and interrupts it',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate()
      ..gate = Completer<void>()
      ..cancelAbortsGate = true;
    await ws.pump(tester, delegate, initialSql: 'SELECT pg_sleep(60)');
    expect(find.text('Cancel'), findsNothing);

    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.enter);
    await E2eSqlWorkspace.settle(tester);
    expect(delegate.executed, ['SELECT pg_sleep(60)']);
    expect(find.text('Cancel'), findsOneWidget);
    expect(delegate.cancelCount, 0);

    await tester.tap(find.text('Cancel'));
    await E2eSqlWorkspace.settle(tester);

    expect(delegate.cancelCount, 1);
    expect(find.textContaining('canceling statement'), findsWidgets);
    expect(find.text('Cancel'), findsNothing);
    // The editor is usable again.
    delegate.gate = null;
    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.enter);
    await E2eSqlWorkspace.settle(tester);
    expect(delegate.executed, hasLength(2));
  });

  testWidgets('a driver without Explain or Cancel hides both buttons',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate()
      ..explainSupported = false
      ..cancelSupported = false
      ..gate = Completer<void>();
    await ws.pump(tester, delegate, initialSql: 'SELECT 1');
    expect(find.text('Explain'), findsNothing);

    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.enter);
    await E2eSqlWorkspace.settle(tester);
    expect(find.text('Cancel'), findsNothing);

    delegate.gate!.complete();
    await E2eSqlWorkspace.settle(tester);
    await tester.pumpWidget(const material.SizedBox());
  });
}
