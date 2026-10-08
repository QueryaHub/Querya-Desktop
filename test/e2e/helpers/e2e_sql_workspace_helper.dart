import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/generic_sql_workspace.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/querya_theme_test_shell.dart';

/// Mounts a [GenericSqlWorkspace] on a fake database for scenarios that do not
/// need the whole shell. The connection row really exists in [LocalDb] because
/// query history is stored with a foreign key to it.
class E2eSqlWorkspace {
  E2eSqlWorkspace._(this.connection);

  final ConnectionRow connection;

  static Future<E2eSqlWorkspace> create({String name = 'E2E SQLite'}) async {
    final row = ConnectionRow(
      type: 'sqlite',
      name: name,
      host: '/tmp/e2e.db',
      createdAt: DateTime.utc(2026).toIso8601String(),
    );
    final id = await LocalDb.instance.addConnection(row);
    return E2eSqlWorkspace._(row.copyWith(id: id));
  }

  Future<GenericSqlWorkspaceState> pump(
    WidgetTester tester,
    FakeSqlExecutionDelegate delegate, {
    String? initialSql,
    SqlDialect dialect = SqlDialect.sqlite,
  }) async {
    await tester.binding.setSurfaceSize(const material.Size(1300, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox.expand(
          child: GenericSqlWorkspace(
            connectionRow: connection,
            delegate: delegate,
            dialect: dialect,
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

  /// Gives the real I/O behind a query time to finish, then pumps.
  static Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  static Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
  }
}
