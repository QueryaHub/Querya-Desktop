import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/erd/erd_catalog.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../helpers/e2e_app_harness.dart';
import '../helpers/e2e_sql_workspace_helper.dart';

const _timeout = Timeout(Duration(seconds: 60));

void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_diagram_');
  late E2eSqlWorkspace ws;
  setUpAll(() async {
    await app.setUpAll();
    ws = await E2eSqlWorkspace.create();
  });
  tearDownAll(app.tearDownAll);
  tearDown(() => SqlEditorCommandBridge.instance
      .unregister(connectionId: ws.connection.id));

  testWidgets('Diagram tab lists tables and opens one on double click',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate(onExecute: (sql) {
      if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
        return const SqlExecutionResult(rows: [
          ['users', 'id', 'INTEGER', '1'],
          ['orders', 'id', 'INTEGER', '1'],
          ['orders', 'user_id', 'INTEGER', '0'],
        ]);
      }
      if (sql == ErdCatalog.foreignKeysSql(SqlDialect.sqlite)) {
        return const SqlExecutionResult(rows: [
          ['orders', 'user_id', 'users', 'id'],
        ]);
      }
      return const SqlExecutionResult(columns: ['id'], rows: [
        ['1'],
      ]);
    });
    final state = await ws.pump(tester, delegate);

    await tester.tap(find.byKey(const material.ValueKey('open_diagram_tab')));
    await E2eSqlWorkspace.settle(tester);
    expect(state.activeSession.isDiagram, isTrue);
    final users = find.byKey(const material.ValueKey('erd_table_users'));
    expect(users, findsOneWidget);
    expect(find.byKey(const material.ValueKey('erd_table_orders')),
        findsOneWidget);

    await tester.tap(users);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(users);
    await E2eSqlWorkspace.settle(tester);

    expect(state.activeSession.isDiagram, isFalse);
    expect(state.activeSession.title, 'users');
    expect(delegate.executed.last, 'SELECT * FROM "users" LIMIT 100;');
  });
}
