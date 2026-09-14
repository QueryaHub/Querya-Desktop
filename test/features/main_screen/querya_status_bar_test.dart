import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/querya_status_bar.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
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
    expect(find.text('UTF-8'), findsOneWidget);
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
    expect(find.text('UTF-8'), findsOneWidget);

    // Test toggle sidebar button
    await tester.tap(find.byTooltip('Toggle Sidebar (Ctrl+B)'));
    expect(toggled, isTrue);
  });
}
