import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
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

    await tester.tap(find.text('New connection'));
    await tester.tap(find.text('New from URL'));
    await tester.tap(find.text('Open SQLite file'));
    expect(newTapped, isTrue);
    expect(urlTapped, isTrue);
    expect(sqliteTapped, isTrue);
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
          child: WorkspaceEmptyHero(onNewConnection: () {}),
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
