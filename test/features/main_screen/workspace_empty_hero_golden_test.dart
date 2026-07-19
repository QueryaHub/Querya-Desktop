import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/workspace_empty_hero.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('empty workspace visual baseline', (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(900, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox.expand(
          child: WorkspaceEmptyHero(
            onNewConnection: () {},
            onNewConnectionFromUrl: () {},
            onOpenSqlite: () {},
            recentConnections: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(WorkspaceEmptyHero),
      matchesGoldenFile('goldens/workspace_empty_hero.png'),
    );
  });
}
