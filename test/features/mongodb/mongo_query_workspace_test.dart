import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_json_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_table_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_query_executor.dart';
import 'package:querya_desktop/features/mongodb/mongo_query_workspace.dart';
import 'package:querya_desktop/features/mongodb/mql_parser.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

class _FakeQueryExecutor implements MongoQueryExecutor {
  _FakeQueryExecutor({this.shouldFail = false});

  List<Map<String, dynamic>>? mockResults;
  bool shouldFail;
  MqlCommand? lastExecutedCommand;

  @override
  Future<MongoQueryResult> execute({
    required MongoConnection connection,
    required String database,
    required MqlCommand command,
    String? defaultCollection,
  }) async {
    lastExecutedCommand = command;
    if (shouldFail) {
      throw const FormatException('Database error: collection not found');
    }
    final docs = mockResults ??
        [
          {'_id': '1', 'name': 'Alice', 'role': 'admin'},
          {'_id': '2', 'name': 'Bob', 'role': 'user'},
        ];
    return MongoQueryResult(
      documents: docs,
      elapsed: const Duration(milliseconds: 45),
      summary: 'Fetched ${docs.length} documents',
    );
  }
}

void main() {
  final testConn = MongoConnection(id: 1, name: 'test', host: 'localhost');

  group('MongoQueryWorkspace', () {
    testWidgets('renders top bar, initial tab, code editor, and run button',
        (tester) async {
      final fakeExecutor = _FakeQueryExecutor();

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoQueryWorkspace(
            connection: testConn,
            database: 'testDb',
            initialCollection: 'users',
            executor: fakeExecutor,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MQL Console — testDb'), findsOneWidget);
      expect(find.text('Query 1'), findsOneWidget);
      expect(find.text('Run Query (Ctrl+Enter)'), findsOneWidget);
      expect(find.text('No Documents to Display'), findsOneWidget);
    });

    testWidgets('adds and closes tabs via QueryaTabStrip', (tester) async {
      final fakeExecutor = _FakeQueryExecutor();

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoQueryWorkspace(
            connection: testConn,
            database: 'testDb',
            executor: fakeExecutor,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Query 1'), findsOneWidget);
      expect(find.text('Query 2'), findsNothing);

      // Add a new tab
      final addTabButton = find.byKey(const material.ValueKey('querya_tab_add_button'));
      expect(addTabButton, findsOneWidget);
      await tester.tap(addTabButton);
      await tester.pumpAndSettle();

      expect(find.text('Query 1'), findsOneWidget);
      expect(find.text('Query 2'), findsOneWidget);

      // Close the second tab
      final closeButtons = find.byIcon(material.Icons.close_rounded);
      expect(closeButtons, findsWidgets);
      await tester.tap(closeButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('Query 2'), findsNothing);
      expect(find.text('Query 1'), findsOneWidget);
    });

    testWidgets('executes MQL query, displays timing and switches Grid / JSON view',
        (tester) async {
      final fakeExecutor = _FakeQueryExecutor();

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoQueryWorkspace(
            connection: testConn,
            database: 'testDb',
            initialCollection: 'users',
            initialQueries: const ['db.users.find({ role: "admin" })'],
            executor: fakeExecutor,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Click "Run Query"
      await tester.tap(find.widgetWithText(PrimaryButton, 'Run Query (Ctrl+Enter)'));
      await tester.pumpAndSettle();

      expect(fakeExecutor.lastExecutedCommand, isNotNull);
      expect(fakeExecutor.lastExecutedCommand!.method, equals(MqlMethod.find));
      expect(fakeExecutor.lastExecutedCommand!.collection, equals('users'));

      // Check results bar
      expect(find.text('Fetched 2 documents'), findsOneWidget);
      expect(find.text('45 ms'), findsOneWidget);
      expect(find.text('2 rows'), findsOneWidget);

      // Default view is Grid (Table)
      expect(find.byType(MongoDocumentsTableView), findsOneWidget);
      expect(find.byType(MongoDocumentsJsonView), findsNothing);

      // Switch to JSON mode
      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();

      expect(find.byType(MongoDocumentsJsonView), findsOneWidget);
      expect(find.byType(MongoDocumentsTableView), findsNothing);
    });

    testWidgets('displays error container when query fails', (tester) async {
      final fakeExecutor = _FakeQueryExecutor(shouldFail: true);

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoQueryWorkspace(
            connection: testConn,
            database: 'testDb',
            initialCollection: 'users',
            executor: fakeExecutor,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrimaryButton, 'Run Query (Ctrl+Enter)'));
      await tester.pumpAndSettle();

      expect(find.text('Query Error'), findsOneWidget);
      expect(find.textContaining('Database error: collection not found'), findsOneWidget);
    });

    testWidgets('triggers query execution via Ctrl+Enter shortcut',
        (tester) async {
      final fakeExecutor = _FakeQueryExecutor();

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoQueryWorkspace(
            connection: testConn,
            database: 'testDb',
            initialCollection: 'users',
            initialQueries: const ['db.users.find({ active: true })'],
            executor: fakeExecutor,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the code editor
      await tester.tap(find.byType(QueryaCodeEditor));
      await tester.pumpAndSettle();

      // Trigger Ctrl+Enter shortcut
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(fakeExecutor.lastExecutedCommand, isNotNull);
      expect(fakeExecutor.lastExecutedCommand!.method, equals(MqlMethod.find));
      expect(fakeExecutor.lastExecutedCommand!.collection, equals('users'));
      expect(find.text('Fetched 2 documents'), findsOneWidget);
    });

    testWidgets('invokes onBack when Back to Documents is pressed',
        (tester) async {
      var backPressed = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoQueryWorkspace(
            connection: testConn,
            database: 'testDb',
            onBack: () => backPressed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to Documents'));
      await tester.pumpAndSettle();

      expect(backPressed, isTrue);
    });
  });
}
