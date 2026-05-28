import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/main_screen/workspace_empty_hero.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('WorkspaceEmptyHero renders with theme tokens', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspaceEmptyHero(onNewConnection: () => tapped = true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('New connection'), findsOneWidget);
    expect(find.textContaining('SELECT'), findsOneWidget);

    await tester.tap(find.text('New connection'));
    expect(tapped, isTrue);
  });

  testWidgets('WorkspaceEmptyHero mock uses workbench surface color', (tester) async {
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

    final container = tester.widgetList<material.Container>(
      find.byType(material.Container),
    ).firstWhere(
      (c) => c.decoration is material.BoxDecoration &&
          (c.decoration! as material.BoxDecoration).color == surface,
    );
    expect(container.decoration, isNotNull);
  });
}
