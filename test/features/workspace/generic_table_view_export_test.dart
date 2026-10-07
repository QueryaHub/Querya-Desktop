import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_filter_bar.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';

import '../../support/fake_table_data_delegate.dart';
import '../../support/generic_table_view_harness.dart';

void main() {
  late List<String> clipboard;

  setUp(() => clipboard = []);

  Future<void> captureClipboard(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  Future<void> copyAs(WidgetTester tester, String menuLabel) async {
    await tester.tap(find.text('Export ▾'));
    await tester.pumpAndSettle();
    // Formatting runs on a background isolate, which needs real async.
    await tester.runAsync(() async {
      await tester.tap(find.text(menuLabel));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
  }

  Future<void> filterBy(WidgetTester tester, String text) async {
    await tester.tap(find.byTooltip('Toggle Quick Filter'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(DataGridFilterBar),
        matching: find.byType(material.TextField),
      ),
      text,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('Copy as CSV exports every row of the page', (tester) async {
    await captureClipboard(tester);
    await pumpGenericTableView(tester, FakeTableDataDelegate());

    await copyAs(tester, 'Copy as CSV');

    expect(clipboard, hasLength(1));
    expect(
      clipboard.single,
      DataExportService.formatCsv(
        const ['id', 'name', 'email'],
        const [
          ['1', 'Alice', 'alice@example.com'],
          ['2', 'Bob', 'bob@example.com'],
          ['3', 'Carol', 'carol@example.com'],
        ],
      ),
    );
  });

  testWidgets('exports follow the quick filter', (tester) async {
    await captureClipboard(tester);
    await pumpGenericTableView(tester, FakeTableDataDelegate());
    await filterBy(tester, 'bob');

    await copyAs(tester, 'Copy as CSV');

    expect(clipboard, hasLength(1));
    expect(clipboard.single, contains('Bob'));
    expect(clipboard.single, isNot(contains('Alice')));
    expect(clipboard.single, isNot(contains('Carol')));
  });

  testWidgets('Copy as JSON contains the filtered values', (tester) async {
    await captureClipboard(tester);
    await pumpGenericTableView(tester, FakeTableDataDelegate());
    await filterBy(tester, 'carol');

    await copyAs(tester, 'Copy as JSON');

    expect(clipboard, hasLength(1));
    expect(clipboard.single, contains('"Carol"'));
    expect(clipboard.single, isNot(contains('Alice')));
  });

  testWidgets('Copy as Markdown Table keeps the header row', (tester) async {
    await captureClipboard(tester);
    await pumpGenericTableView(tester, FakeTableDataDelegate());

    await copyAs(tester, 'Copy as Markdown Table');

    expect(clipboard, hasLength(1));
    expect(clipboard.single, contains('| id | name | email |'));
    expect(clipboard.single, contains('Alice'));
  });

  testWidgets('Copy as SQL Dump writes INSERT statements', (tester) async {
    await captureClipboard(tester);
    await pumpGenericTableView(tester, FakeTableDataDelegate());
    await filterBy(tester, 'alice');

    await copyAs(tester, 'Copy as SQL Dump');

    expect(clipboard, hasLength(1));
    expect(clipboard.single, contains('INSERT INTO'));
    expect(clipboard.single, contains("'Alice'"));
    expect(clipboard.single, isNot(contains('Bob')));
  });
}
