import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/workspace/query_plan.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_session.dart';
import 'package:querya_desktop/features/workspace/sql_result_grid_schema.dart';
import 'package:querya_desktop/features/workspace/sql_workspace_toolbar.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class _FakeSqlExecutionDelegate extends BaseSqlExecutionDelegate {
  @override
  Future<SqlExecutionResult> executeQuery(
    String sql, {
    int? limit,
    Duration? timeout,
  }) async =>
      const SqlExecutionResult();

  @override
  Future<String> explainQuery(String sql) async => 'EXPLAIN PLAN';

  @override
  Future<void> cancelQuery() async {}

  @override
  bool get supportsTransactions => true;

  @override
  bool get supportsExplain => true;

  @override
  bool get supportsCancel => true;
}

void main() {
  Widget buildApp(Widget child) {
    return ShadcnApp(
      theme: ThemeData.dark(),
      home: QueryaThemeScope(
        theme: QueryaTheme.darkDefault,
        child: material.Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('BaseSqlExecutionDelegate', () {
    test('formats status message for empty result with affected rows', () {
      final delegate = _FakeSqlExecutionDelegate();
      final msg = delegate.formatStatusMessage(
        columnCount: 0,
        rowCount: 0,
        affectedRows: 5,
        isTruncated: false,
        cap: 1000,
      );
      expect(msg, 'OK. Rows affected: 5.');
    });

    test('formats status message for truncated results', () {
      final delegate = _FakeSqlExecutionDelegate();
      final msg = delegate.formatStatusMessage(
        columnCount: 2,
        rowCount: 100,
        isTruncated: true,
        cap: 100,
      );
      expect(msg, 'Showing first 100 row(s) (result capped).');
    });

    test('formats status message for normal results', () {
      final delegate = _FakeSqlExecutionDelegate();
      final msg = delegate.formatStatusMessage(
        columnCount: 2,
        rowCount: 42,
        isTruncated: false,
        cap: 100,
      );
      expect(msg, '42 row(s).');
    });
  });

  group('SqlWorkspaceToolbar', () {
    testWidgets('renders action buttons and handles execution callback',
        (tester) async {
      final session = SqlQueryTabSession(
        id: '1',
        title: 'Query 1',
        initialSql: 'SELECT 1;',
      );
      final delegate = _FakeSqlExecutionDelegate();
      bool executeCalled = false;

      await tester.pumpWidget(
        buildApp(
          SqlWorkspaceToolbar(
            session: session,
            delegate: delegate,
            effectiveDatabase: 'test_db',
            autocommit: true,
            supportsAutocommit: true,
            supportsStmtTimeout: true,
            txOpen: false,
            queryTimeoutSeconds: null,
            historyEnabled: true,
            onExecute: (statementAtCursor) => executeCalled = true,
            onExplain: () {},
            onCancel: () {},
            onOpenHistory: () {},
            onOpenFile: () {},
            onSaveFile: () {},
            onRunTxCommand: (_) {},
            onToggleAutocommit: () {},
            onTimeoutChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const material.ValueKey('run_script')), findsOneWidget);
      expect(find.byKey(const material.ValueKey('explain_query')), findsOneWidget);
      expect(find.text('test_db'), findsOneWidget);

      await tester.tap(find.byKey(const material.ValueKey('run_script')));
      expect(executeCalled, isTrue);
    });
  });
}
