import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/main_screen/workspace_empty_hero.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('WorkspaceEmptyHero renders with theme tokens', (tester) async {
    var newTapped = false;
    var urlTapped = false;
    var sqliteTapped = false;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspaceEmptyHero(
            onNewConnection: () => newTapped = true,
            onNewConnectionFromUrl: () => urlTapped = true,
            onOpenSqlite: () => sqliteTapped = true,
            recentConnections: const [],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('New connection'), findsOneWidget);
    expect(find.text('New from URL'), findsOneWidget);
    expect(find.text('Open SQLite file'), findsOneWidget);
    expect(find.text('Start working with your data'), findsOneWidget);
    expect(find.textContaining('dark interface'), findsNothing);
    expect(find.text('Quick start'), findsOneWidget);

    await tester.tap(find.text('New connection'));
    await tester.tap(find.text('New from URL'));
    await tester.tap(find.text('Open SQLite file'));
    expect(newTapped, isTrue);
    expect(urlTapped, isTrue);
    expect(sqliteTapped, isTrue);
  });

  testWidgets('WorkspaceEmptyHero opens a recent connection', (tester) async {
    ConnectionRow? opened;
    const recent = ConnectionRow(
      id: 7,
      type: 'postgresql',
      name: 'Prod DB',
      host: 'db.example.com',
      port: 5432,
      createdAt: '2026-01-01T00:00:00Z',
    );

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspaceEmptyHero(
            onNewConnection: () {},
            recentConnections: const [recent],
            onOpenConnection: (conn) => opened = conn,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recent connections'), findsOneWidget);
    expect(find.text('Prod DB'), findsOneWidget);
    expect(find.text('db.example.com:5432'), findsOneWidget);
    expect(find.text('Quick start'), findsNothing);

    await tester.tap(find.text('Prod DB'));
    expect(opened?.id, 7);
  });

  testWidgets('WorkspaceEmptyHero quick start uses workbench surface color',
      (tester) async {
    const surface = material.Color(0xFFABCDEF);
    final theme = QueryaTheme.darkDefault.copyWith(
      workbench: QueryaTheme.darkDefault.workbench.copyWith(surface: surface),
    );

    await tester.pumpWidget(
      queryaThemeTestShell(
        data: theme,
        child: material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspaceEmptyHero(
            onNewConnection: () {},
            recentConnections: const [],
          ),
        ),
      ),
    );
    await tester.pump();

    final container = tester
        .widgetList<material.Container>(
          find.byType(material.Container),
        )
        .firstWhere(
          (c) =>
              c.decoration is material.BoxDecoration &&
              (c.decoration! as material.BoxDecoration).color == surface,
        );
    expect(container.decoration, isNotNull);
  });
}
