import 'dart:io' show Platform;

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/ui/querya_shell_status.dart';
import 'package:querya_desktop/features/main_screen/querya_status_bar.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  tearDown(QueryaShellStatus.instance.resetForTest);

  testWidgets('QueryaStatusBar renders empty status when no connection',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.Scaffold(
          body: QueryaStatusBar(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No connection'), findsOneWidget);
    expect(find.text('UTF-8'), findsNothing);
  });

  testWidgets('QueryaStatusBar renders active connection and read-only mode',
      (tester) async {
    final conn = ConnectionRow(
      id: 1,
      name: 'Prod Postgres',
      type: 'postgresql',
      host: '10.0.0.1',
      port: 5432,
      createdAt: DateTime.now().toIso8601String(),
    );

    var toggled = false;

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: QueryaStatusBar(
            activeConnection: conn,
            isReadOnly: true,
            rowCount: 250,
            columnCount: 12,
            lastQueryDuration: const Duration(milliseconds: 42),
            onToggleSidebar: () => toggled = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Prod Postgres'), findsOneWidget);
    expect(find.text('(10.0.0.1:5432)'), findsOneWidget);
    expect(find.text('Read-only'), findsOneWidget);
    expect(find.text('250 rows, 12 cols'), findsOneWidget);
    expect(find.text('42 ms'), findsOneWidget);

    await tester.tap(find.byKey(const material.Key('status_bar_toggle_sidebar')));
    expect(toggled, isTrue);
  });

  test('QueryaShellStatus reports busy and query metrics', () {
    final status = QueryaShellStatus.instance;
    var ticks = 0;
    status.addListener(() => ticks++);

    status.beginBusy(message: 'Running query…');
    expect(status.isBusy, isTrue);
    expect(status.statusMessage, 'Running query…');

    status.reportQueryResult(
      duration: const Duration(milliseconds: 17),
      rowCount: 3,
      columnCount: 2,
      message: '3 row(s).',
    );
    expect(status.isBusy, isFalse);
    expect(status.lastQueryDuration, const Duration(milliseconds: 17));
    expect(status.rowCount, 3);
    expect(status.columnCount, 2);
    expect(ticks, greaterThanOrEqualTo(2));

    status.clear();
    expect(status.rowCount, isNull);
  });

  testWidgets('sidebar tooltip mentions platform modifier', (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: QueryaStatusBar(
            onToggleSidebar: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final expected = Platform.isMacOS
        ? 'Toggle Sidebar (Cmd+B)'
        : 'Toggle Sidebar (Ctrl+B)';
    expect(find.byTooltip(expected), findsOneWidget);
  });
}
