import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/sql_query_history_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const connectionId = 999;
  const databaseName = 'test_db';

  var clipboardContent = '';
  setUp(() {
    clipboardContent = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          clipboardContent = (methodCall.arguments as Map)['text'] as String;
          return null;
        }
        if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clipboardContent};
        }
        return null;
      },
    );
  });

  SqlQueryHistoryEntry makeEntry(String sql, {int id = 1}) {
    return SqlQueryHistoryEntry(
      id: id,
      connectionId: connectionId,
      databaseName: databaseName,
      sqlText: sql,
      recordedAt: '2026-09-24T10:00:00.000Z',
    );
  }

  testWidgets('applies directly without prompt when active editor is empty', (tester) async {
    final controller = material.TextEditingController();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.ElevatedButton(
            onPressed: () {
              showSqlQueryHistoryDialog(
                context: context,
                connectionId: connectionId,
                databaseName: databaseName,
                sqlController: controller,
                loadHistory: () async => [makeEntry('SELECT 100;')],
              );
            },
            child: const material.Text('Open History'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open History'));
    await tester.pumpAndSettle();

    expect(find.text('Query history'), findsOneWidget);
    expect(find.text('SELECT 100;'), findsOneWidget);

    // Tap the row
    await tester.tap(find.text('SELECT 100;'));
    await tester.pumpAndSettle();

    // Editor is populated and dialog is closed
    expect(controller.text, 'SELECT 100;');
    expect(find.text('Query history'), findsNothing);
  });

  testWidgets('applies directly without prompt when active editor has same text', (tester) async {
    final controller = material.TextEditingController(text: 'SELECT 100;');

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.ElevatedButton(
            onPressed: () {
              showSqlQueryHistoryDialog(
                context: context,
                connectionId: connectionId,
                databaseName: databaseName,
                sqlController: controller,
                loadHistory: () async => [makeEntry('SELECT 100;')],
              );
            },
            child: const material.Text('Open History'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open History'));
    await tester.pumpAndSettle();

    // Tap the row
    await tester.tap(find.text('SELECT 100;'));
    await tester.pumpAndSettle();

    expect(find.text('Replace editor content?'), findsNothing);
    expect(controller.text, 'SELECT 100;');
    expect(find.text('Query history'), findsNothing);
  });

  testWidgets('prompts confirmation when editor has existing text and allows Cancel', (tester) async {
    final controller = material.TextEditingController(text: 'SELECT custom_work;');

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.ElevatedButton(
            onPressed: () {
              showSqlQueryHistoryDialog(
                context: context,
                connectionId: connectionId,
                databaseName: databaseName,
                sqlController: controller,
                loadHistory: () async => [makeEntry('SELECT * FROM users;')],
              );
            },
            child: const material.Text('Open History'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open History'));
    await tester.pumpAndSettle();

    // Tap the history entry
    await tester.tap(find.text('SELECT * FROM users;'));
    await tester.pumpAndSettle();

    // Confirmation dialog is shown
    expect(find.text('Replace editor content?'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Cancel retains original editor content
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(controller.text, 'SELECT custom_work;');
    expect(find.text('Query history'), findsOneWidget);
  });

  testWidgets('confirms replace when user chooses Replace', (tester) async {
    final controller = material.TextEditingController(text: 'SELECT custom_work;');

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.ElevatedButton(
            onPressed: () {
              showSqlQueryHistoryDialog(
                context: context,
                connectionId: connectionId,
                databaseName: databaseName,
                sqlController: controller,
                loadHistory: () async => [makeEntry('SELECT * FROM users;')],
              );
            },
            child: const material.Text('Open History'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open History'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SELECT * FROM users;'));
    await tester.pumpAndSettle();

    expect(find.text('Replace editor content?'), findsOneWidget);

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();

    expect(controller.text, 'SELECT * FROM users;');
    expect(find.text('Query history'), findsNothing);
  });

  testWidgets('allows Open in New Tab from confirmation dialog', (tester) async {
    final controller = material.TextEditingController(text: 'SELECT my_draft;');
    String? newTabSql;

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.ElevatedButton(
            onPressed: () {
              showSqlQueryHistoryDialog(
                context: context,
                connectionId: connectionId,
                databaseName: databaseName,
                sqlController: controller,
                onOpenInNewTab: (sql) => newTabSql = sql,
                loadHistory: () async => [makeEntry('SELECT * FROM orders;')],
              );
            },
            child: const material.Text('Open History'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open History'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SELECT * FROM orders;'));
    await tester.pumpAndSettle();

    expect(find.text('Open in New Tab'), findsOneWidget);

    await tester.tap(find.text('Open in New Tab'));
    await tester.pumpAndSettle();

    expect(newTabSql, 'SELECT * FROM orders;');
    // Original editor is untouched
    expect(controller.text, 'SELECT my_draft;');
    expect(find.text('Query history'), findsNothing);
  });

  testWidgets('quick action button opens in new tab directly', (tester) async {
    final controller = material.TextEditingController(text: 'SELECT untouched;');
    String? newTabSql;

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.ElevatedButton(
            onPressed: () {
              showSqlQueryHistoryDialog(
                context: context,
                connectionId: connectionId,
                databaseName: databaseName,
                sqlController: controller,
                onOpenInNewTab: (sql) => newTabSql = sql,
                loadHistory: () async => [makeEntry('SELECT quick_tab;')],
              );
            },
            child: const material.Text('Open History'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open History'));
    await tester.pumpAndSettle();

    final openTabIcon = find.byIcon(material.Icons.open_in_new_rounded);
    expect(openTabIcon, findsOneWidget);

    await tester.tap(openTabIcon);
    await tester.pumpAndSettle();

    expect(newTabSql, 'SELECT quick_tab;');
    expect(controller.text, 'SELECT untouched;');
    expect(find.text('Query history'), findsNothing);
  });

  testWidgets('quick action copy to clipboard copies text', (tester) async {
    final controller = material.TextEditingController();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.ElevatedButton(
            onPressed: () {
              showSqlQueryHistoryDialog(
                context: context,
                connectionId: connectionId,
                databaseName: databaseName,
                sqlController: controller,
                loadHistory: () async => [makeEntry('SELECT copy_me;')],
              );
            },
            child: const material.Text('Open History'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open History'));
    await tester.pumpAndSettle();

    final copyIcon = find.byIcon(material.Icons.copy_rounded);
    expect(copyIcon, findsOneWidget);

    await tester.tap(copyIcon);
    await tester.pumpAndSettle();

    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboardData?.text, 'SELECT copy_me;');
    expect(find.text('Query copied to clipboard'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
