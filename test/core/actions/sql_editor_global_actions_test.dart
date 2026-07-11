import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_connection_types.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/actions/sql_editor_global_actions.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

import '../../support/querya_theme_test_shell.dart';

ConnectionRow _postgresConnection() => const ConnectionRow(
      id: 1,
      type: 'postgresql',
      name: 'Local PG',
      createdAt: '2026-01-01T00:00:00.000Z',
    );

void main() {
  tearDown(SqlEditorCommandBridge.instance.resetForTest);

  group('isSqlCapableConnection', () {
    test('accepts postgres mysql sqlite', () {
      expect(isSqlCapableConnection(_postgresConnection()), isTrue);
      expect(
        isSqlCapableConnection(
          const ConnectionRow(
            id: 2,
            type: 'redis',
            name: 'Redis',
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        ),
        isFalse,
      );
    });
  });

  testWidgets('NewSqlIntent opens sql workspace for sql-capable connection',
      (tester) async {
    ConnectionRow? opened;

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.ScaffoldMessenger(
          child: material.Scaffold(
            body: SqlEditorGlobalActions(
              activeConnection: _postgresConnection(),
              onOpenSqlWorkspace: (connection) => opened = connection,
              child: material.Builder(
                builder: (context) {
                  return material.ElevatedButton(
                    onPressed: () {
                      Actions.invoke(context, const NewSqlIntent());
                    },
                    child: const material.Text('invoke'),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('invoke'));
    await tester.pump();

    expect(opened?.type, 'postgresql');
    expect(
      SqlEditorCommandBridge.instance.pendingAction,
      SqlEditorPendingAction.newQuery,
    );
  });

  testWidgets('NewSqlIntent shows hint when connection is not sql-capable',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.ScaffoldMessenger(
          child: material.Scaffold(
            body: SqlEditorGlobalActions(
              activeConnection: const ConnectionRow(
                id: 3,
                type: 'mongodb',
                name: 'Mongo',
                createdAt: '2026-01-01T00:00:00.000Z',
              ),
              onOpenSqlWorkspace: (_) {},
              child: material.Builder(
                builder: (context) {
                  return material.ElevatedButton(
                    onPressed: () {
                      Actions.invoke(context, const NewSqlIntent());
                    },
                    child: const material.Text('invoke'),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('invoke'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(
        'Select a SQL-capable connection (PostgreSQL, MySQL, SQLite, or an installed driver) to edit SQL files.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('OpenSqlIntent delegates to active sql editor bridge',
      (tester) async {
    var openCount = 0;
    SqlEditorCommandBridge.instance.register(
      connectionId: 1,
      onNew: () {},
      onOpen: () => openCount++,
      onSave: () {},
    );

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.ScaffoldMessenger(
          child: material.Scaffold(
            body: SqlEditorGlobalActions(
              activeConnection: _postgresConnection(),
              onOpenSqlWorkspace: (_) => fail('should not open workspace'),
              child: material.Builder(
                builder: (context) {
                  return material.ElevatedButton(
                    onPressed: () {
                      Actions.invoke(context, const OpenSqlIntent());
                    },
                    child: const material.Text('invoke'),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('invoke'));
    await tester.pump();

    expect(openCount, 1);
  });
}
