import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_fade_slide.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/motion/querya_stagger.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/main_screen/workspace_empty_hero.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  const recent = ConnectionRow(
    id: 7,
    type: 'postgresql',
    name: 'Prod DB',
    host: 'db.example.com',
    port: 5432,
    createdAt: '2026-01-01T00:00:00Z',
  );

  material.Widget heroShell({
    required material.Widget child,
    QueryaMotionLevel level = QueryaMotionLevel.full,
    QueryaTheme? theme,
  }) {
    return queryaThemeTestShell(
      data: theme ?? QueryaTheme.darkDefault,
      child: QueryaMotionScope(
        level: level,
        child: child,
      ),
    );
  }

  testWidgets('WorkspaceEmptyHero renders with theme tokens', (tester) async {
    var newTapped = false;
    var urlTapped = false;
    var sqliteTapped = false;
    await tester.pumpWidget(
      heroShell(
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
    expect(find.byType(QueryaFadeSlide), findsOneWidget);
    expect(
      find.byKey(const material.ValueKey('empty_quick_start')),
      findsOneWidget,
    );

    await tester.tap(find.text('New connection'));
    await tester.tap(find.text('New from URL'));
    await tester.tap(find.text('Open SQLite file'));
    expect(newTapped, isTrue);
    expect(urlTapped, isTrue);
    expect(sqliteTapped, isTrue);
  });

  testWidgets('does not flash Quick start before recent load completes',
      (tester) async {
    await tester.pumpWidget(
      heroShell(
        child: material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspaceEmptyHero(
            onNewConnection: () {},
          ),
        ),
      ),
    );
    // First frame before async recent load settles.
    await tester.pump();

    expect(
      find.byKey(const material.ValueKey('empty_section_loading')),
      findsOneWidget,
    );
    expect(find.text('Quick start'), findsNothing);
    expect(find.text('Recent connections'), findsNothing);
  });

  testWidgets('WorkspaceEmptyHero opens a recent connection', (tester) async {
    ConnectionRow? opened;

    await tester.pumpWidget(
      heroShell(
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
    await tester.pumpAndSettle();

    expect(find.text('Recent connections'), findsOneWidget);
    expect(find.text('Prod DB'), findsOneWidget);
    expect(find.text('db.example.com:5432'), findsOneWidget);
    expect(find.text('Quick start'), findsNothing);
    expect(find.byType(QueryaStagger), findsOneWidget);
    expect(
      find.byKey(const material.ValueKey('empty_recent_section')),
      findsOneWidget,
    );

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
      heroShell(
        theme: theme,
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

  testWidgets('morphs quick start into recent list with FadeSlide',
      (tester) async {
    await tester.pumpWidget(
      heroShell(
        child: const material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspaceEmptyHero(
            onNewConnection: _noop,
            recentConnections: [],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Quick start'), findsOneWidget);

    await tester.pumpWidget(
      heroShell(
        child: material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspaceEmptyHero(
            onNewConnection: _noop,
            recentConnections: const [recent],
            onOpenConnection: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    // During transition both panels may briefly coexist in AnimatedSwitcher.
    expect(find.text('Recent connections'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Quick start'), findsNothing);
    expect(find.text('Prod DB'), findsOneWidget);
  });

  testWidgets('motion off snaps quick start → recent without overlap',
      (tester) async {
    await tester.pumpWidget(
      heroShell(
        level: QueryaMotionLevel.off,
        child: const material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspaceEmptyHero(
            onNewConnection: _noop,
            recentConnections: [],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      heroShell(
        level: QueryaMotionLevel.off,
        child: const material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspaceEmptyHero(
            onNewConnection: _noop,
            recentConnections: [recent],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Quick start'), findsNothing);
    expect(find.text('Recent connections'), findsOneWidget);
  });

  testWidgets('recent list staggers on first paint then reaches full opacity',
      (tester) async {
    const second = ConnectionRow(
      id: 8,
      type: 'mysql',
      name: 'Analytics',
      host: 'mysql.local',
      port: 3306,
      createdAt: '2026-01-02T00:00:00Z',
    );

    await tester.pumpWidget(
      heroShell(
        child: const material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspaceEmptyHero(
            onNewConnection: _noop,
            recentConnections: [recent, second],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));

    double opacityOf(String label) {
      return tester
          .widget<material.Opacity>(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byType(material.Opacity),
                )
                .first,
          )
          .opacity;
    }

    expect(opacityOf('Prod DB'), greaterThanOrEqualTo(opacityOf('Analytics')));
    await tester.pumpAndSettle();
    expect(opacityOf('Prod DB'), 1.0);
    expect(opacityOf('Analytics'), 1.0);
  });
}

void _noop() {}
