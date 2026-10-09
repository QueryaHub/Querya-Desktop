import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../helpers/e2e_app_harness.dart';
import '../helpers/e2e_sql_workspace_helper.dart';

const _timeout = Timeout(Duration(seconds: 60));

/// A database that really tracks `BEGIN` / `COMMIT` / `ROLLBACK`.
class _TxDelegate extends FakeSqlExecutionDelegate {
  var open = false;
  final commands = <String>[];

  @override
  bool get supportsTransactions => true;

  @override
  Future<void> runTransactionCommand(String command,
      {Duration? timeout}) async {
    commands.add(command);
    open = command == 'BEGIN';
  }

  @override
  Future<bool?> checkTransactionOpen() async => open;
}

void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_tx_');
  late E2eSqlWorkspace ws;
  setUpAll(() async {
    await app.setUpAll();
    ws = await E2eSqlWorkspace.create();
  });
  tearDownAll(app.tearDownAll);

  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await E2eSqlWorkspace.settle(tester);
  }

  testWidgets('Begin opens a transaction, Rollback and Commit close it',
      timeout: _timeout, (tester) async {
    final delegate = _TxDelegate();
    await ws.pump(tester, delegate);
    await E2eSqlWorkspace.settle(tester);
    // Unknown until the first command refreshes the state.
    expect(find.text('Transaction —'), findsOneWidget);

    await tapAndSettle(tester, 'Begin');
    expect(find.text('Transaction open'), findsOneWidget);
    expect(find.text('OK: BEGIN'), findsWidgets);

    await tapAndSettle(tester, 'Rollback');
    expect(find.text('Auto-commit'), findsOneWidget);

    await tapAndSettle(tester, 'Begin');
    await tapAndSettle(tester, 'Commit');
    expect(find.text('Auto-commit'), findsOneWidget);

    expect(delegate.commands, ['BEGIN', 'ROLLBACK', 'BEGIN', 'COMMIT']);
  });

  testWidgets('a database without transactions shows no transaction controls',
      timeout: _timeout, (tester) async {
    await ws.pump(tester, FakeSqlExecutionDelegate());

    expect(find.text('Begin'), findsNothing);
    expect(find.text('Commit'), findsNothing);
    expect(find.text('Rollback'), findsNothing);
  });

  testWidgets('a destructive statement waits for confirmation',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    await ws.pump(tester, delegate, initialSql: 'DELETE FROM users');

    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.enter);
    await E2eSqlWorkspace.settle(tester);
    expect(find.text('Execute Destructive Statement'), findsOneWidget);
    expect(delegate.executed, isEmpty);

    await tester.tap(find.text('Cancel'));
    await E2eSqlWorkspace.settle(tester);
    expect(delegate.executed, isEmpty);

    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.enter);
    await E2eSqlWorkspace.settle(tester);
    // The button stays disabled until the warning is acknowledged.
    await tester.tap(find.text('Execute Destructive Statement'),
        warnIfMissed: false);
    await E2eSqlWorkspace.settle(tester);
    expect(delegate.executed, isEmpty);
    await tester.tap(find.byType(material.Checkbox));
    await tester.pump();
    await tester.tap(find.text('Execute Destructive Statement'));
    await E2eSqlWorkspace.settle(tester);
    expect(delegate.executed, ['DELETE FROM users']);
  });

  testWidgets('closing the workspace while a query runs cancels it',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate()..gate = Completer<void>();
    await ws.pump(tester, delegate, initialSql: 'SELECT pg_sleep(60)');

    await E2eSqlWorkspace.ctrl(tester, LogicalKeyboardKey.enter);
    await E2eSqlWorkspace.settle(tester);
    expect(delegate.executed, ['SELECT pg_sleep(60)']);
    expect(delegate.cancelCount, 0);

    await tester.pumpWidget(const material.SizedBox());
    await tester.pump();

    expect(delegate.cancelCount, 1);
    delegate.gate!.complete();
    await E2eSqlWorkspace.settle(tester);
  });
}
