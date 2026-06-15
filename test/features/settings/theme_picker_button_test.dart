import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_definition.dart';
import 'package:querya_desktop/core/theme/theme_metadata.dart';
import 'package:querya_desktop/features/settings/theme_picker_button.dart';
import 'package:querya_desktop/features/settings/theme_preview_card.dart';

import '../../support/querya_theme_test_shell.dart';

List<ThemeDefinition> _fakeThemes(int count) {
  return List.generate(
    count,
    (index) => ThemeDefinition(
      id: 'theme-$index',
      name: 'Theme ${index.toString().padLeft(2, '0')}',
      source: ThemeSource.values[index % ThemeSource.values.length],
      format: index.isEven ? ThemeFormat.queryaCustom : ThemeFormat.vscode,
      isDark: index.isOdd,
    ),
  );
}

void main() {
  group('filterThemeDefinitions', () {
    final themes = _fakeThemes(10);

    test('filters by theme name', () {
      final filtered = filterThemeDefinitions(themes, 'theme 03');
      expect(filtered, hasLength(1));
      expect(filtered.single.id, 'theme-3');
    });

    test('filters by theme id', () {
      final filtered = filterThemeDefinitions(themes, 'theme-7');
      expect(filtered, hasLength(1));
      expect(filtered.single.name, 'Theme 07');
    });

    test('filters by source label', () {
      final filtered = filterThemeDefinitions(themes, 'file');
      expect(filtered, isNotEmpty);
      expect(
        filtered.every((theme) => theme.source == ThemeSource.filesystem),
        isTrue,
      );
    });
  });

  group('ThemePickerButton', () {
    testWidgets('builds MenuAnchor trigger for many themes', (tester) async {
      final themes = _fakeThemes(60);

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: themes,
              selectedThemeId: 'theme-5',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(material.MenuAnchor), findsOneWidget);
      expect(find.text('Theme 05'), findsOneWidget);
      expect(find.byType(material.ListView), findsNothing);
    });

    testWidgets('opens scrollable menu and renders visible rows', (tester) async {
      final themes = _fakeThemes(60);

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: themes,
              selectedThemeId: 'theme-0',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Theme 00'));
      await tester.pumpAndSettle();

      expect(find.byType(material.ListView), findsOneWidget);
      expect(find.byType(material.Scrollbar), findsWidgets);
      expect(find.text('Theme 00'), findsWidgets);
      expect(find.text('Theme 01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap row triggers onSelected with theme id', (tester) async {
      final themes = _fakeThemes(60);
      String? picked;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: themes,
              selectedThemeId: 'theme-0',
              onSelected: (id) => picked = id,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Theme 00'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Theme 01'));
      await tester.pumpAndSettle();

      expect(picked, 'theme-1');
    });

    testWidgets('shows source badge and brightness label in open menu',
        (tester) async {
      const themes = [
        ThemeDefinition(
          id: 'builtin-dark',
          name: 'Querya Dark',
          source: ThemeSource.builtin,
          format: ThemeFormat.queryaCustom,
          isDark: true,
        ),
        ThemeDefinition(
          id: 'file-light',
          name: 'Sunrise',
          source: ThemeSource.filesystem,
          format: ThemeFormat.vscode,
          isDark: false,
        ),
      ];

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: themes,
              selectedThemeId: 'builtin-dark',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Querya Dark'));
      await tester.pumpAndSettle();

      expect(find.text('Built-in'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
    });

    testWidgets('loading state disables menu open', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: _fakeThemes(3),
              selectedThemeId: null,
              onSelected: (_) {},
              isLoading: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Loading themes…'), findsOneWidget);

      await tester.tap(find.text('Loading themes…'));
      await tester.pumpAndSettle();

      expect(find.byType(material.ListView), findsNothing);
    });
  });

  group('ThemePickerButton large list', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.text('Theme 00'));
      await tester.pumpAndSettle();
    }

    testWidgets('uses ListView.builder for 60 themes without overflow',
        (tester) async {
      final themes = _fakeThemes(60);

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: themes,
              selectedThemeId: 'theme-0',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      expect(tester.takeException(), isNull);
      final listView = tester.widget<material.ListView>(
        find.byType(material.ListView),
      );
      final delegate = listView.childrenDelegate;
      expect(delegate, isA<material.SliverChildBuilderDelegate>());
      expect(
        (delegate as material.SliverChildBuilderDelegate).childCount,
        60,
      );
    });

    testWidgets('builds only a visible subset of 60 theme rows', (tester) async {
      final themes = _fakeThemes(60);

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: themes,
              selectedThemeId: 'theme-0',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      var visibleCount = 0;
      for (var index = 0; index < 60; index++) {
        final label = 'Theme ${index.toString().padLeft(2, '0')}';
        final row = find.descendant(
          of: find.byType(material.ListView),
          matching: find.text(label),
        );
        if (row.evaluate().isNotEmpty) visibleCount++;
      }

      expect(visibleCount, greaterThan(3));
      expect(visibleCount, lessThan(60));
      expect(
        find.descendant(
          of: find.byType(material.ListView),
          matching: find.text('Theme 59'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('selects last theme from large list', (tester) async {
      final themes = _fakeThemes(60);
      String? picked;
      var selectedId = 'theme-0';

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.StatefulBuilder(
              builder: (context, setState) {
                return ThemePickerButton(
                  themes: themes,
                  selectedThemeId: selectedId,
                  onSelected: (id) {
                    picked = id;
                    setState(() => selectedId = id);
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      await tester.enterText(find.byType(material.TextField), 'Theme 59');
      await tester.pump();

      await tester.tap(
        find.descendant(
          of: find.byType(material.ListView),
          matching: find.text('Theme 59'),
        ),
      );
      await tester.pumpAndSettle();

      expect(picked, 'theme-59');
      expect(find.text('Theme 59'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ThemePickerButton search', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.text('Theme 00'));
      await tester.pumpAndSettle();
    }

    testWidgets('filters visible rows by theme name', (tester) async {
      final themes = _fakeThemes(60);

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: themes,
              selectedThemeId: 'theme-0',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      await tester.enterText(find.byType(material.TextField), 'Theme 05');
      await tester.pump();

      expect(find.text('Theme 01'), findsNothing);
      expect(find.text('Theme 59'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(material.ListView),
          matching: find.text('Theme 05'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows empty message when filter has no results', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: _fakeThemes(20),
              selectedThemeId: 'theme-0',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      await tester.enterText(find.byType(material.TextField), 'zzzz-no-match');
      await tester.pump();

      expect(find.text('No themes match your search.'), findsOneWidget);
      expect(find.byType(material.ListView), findsNothing);
    });

    testWidgets('clearing search restores full list', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: _fakeThemes(20),
              selectedThemeId: 'theme-0',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      await tester.enterText(find.byType(material.TextField), 'Theme 05');
      await tester.pump();
      expect(find.text('Theme 01'), findsNothing);

      await tester.enterText(find.byType(material.TextField), '');
      await tester.pump();

      expect(find.text('Theme 01'), findsOneWidget);
      expect(find.text('No themes match your search.'), findsNothing);
    });

    testWidgets('typing in search does not call onSelected', (tester) async {
      var selectionCount = 0;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: _fakeThemes(20),
              selectedThemeId: 'theme-0',
              onSelected: (_) => selectionCount++,
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      await tester.enterText(find.byType(material.TextField), 'Theme 03');
      await tester.pumpAndSettle();

      expect(selectionCount, 0);
    });
  });

  group('ThemePickerButton preview', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.text('Theme 00'));
      await tester.pumpAndSettle();
    }

    Future<void> hoverRow(WidgetTester tester, String rowLabel) async {
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(find.text(rowLabel)));
      await tester.pump();
    }

    testWidgets('hover does not call onSelected', (tester) async {
      var selectionCount = 0;
      var previewCount = 0;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: _fakeThemes(20),
              selectedThemeId: 'theme-0',
              onSelected: (_) => selectionCount++,
              onPreviewTheme: (_) async {
                previewCount++;
                return const ThemePreviewResult.theme(QueryaTheme.darkDefault);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      await hoverRow(tester, 'Theme 01');
      await tester.pump(themePreviewDebounce);
      await tester.pump();

      expect(selectionCount, 0);
      expect(previewCount, 1);
      expect(find.text('Sample text'), findsOneWidget);
    });

    testWidgets('preview future resolves and card updates after debounce',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: _fakeThemes(20),
              selectedThemeId: 'theme-0',
              onSelected: (_) {},
              onPreviewTheme: (_) async {
                await Future<void>.delayed(const Duration(milliseconds: 20));
                return const ThemePreviewResult.theme(QueryaTheme.lightDefault);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      await hoverRow(tester, 'Theme 02');
      await tester.pump(themePreviewDebounce);
      expect(find.text('Loading preview…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Theme 02'), findsWidgets);
      expect(find.text('Sample text'), findsOneWidget);
      expect(find.text('Loading preview…'), findsNothing);
    });

    testWidgets('broken preview shows fallback error in card', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: _fakeThemes(20),
              selectedThemeId: 'theme-0',
              onSelected: (_) {},
              onPreviewTheme: (_) async {
                return const ThemePreviewResult.error('Could not parse theme');
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      await hoverRow(tester, 'Theme 03');
      await tester.pump(themePreviewDebounce);
      await tester.pump();

      expect(find.text('Could not parse theme'), findsOneWidget);
      expect(find.text('Sample text'), findsNothing);
    });

    testWidgets('shows preview card only when onPreviewTheme is provided',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: _fakeThemes(5),
              selectedThemeId: 'theme-0',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await openMenu(tester);

      expect(find.byType(ThemePreviewCard), findsNothing);
    });

    testWidgets('tap row still selects when onPreviewTheme is provided',
        (tester) async {
      String? picked;
      const themes = [
        ThemeDefinition(
          id: ThemeController.builtinQueryaDarkId,
          name: 'Querya Dark',
          source: ThemeSource.builtin,
          format: ThemeFormat.queryaCustom,
          isDark: true,
        ),
        ThemeDefinition(
          id: ThemeController.builtinQueryaLightId,
          name: 'Querya Light',
          source: ThemeSource.builtin,
          format: ThemeFormat.queryaCustom,
          isDark: false,
        ),
      ];

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ThemePickerButton(
              themes: themes,
              selectedThemeId: ThemeController.builtinQueryaDarkId,
              expandToParent: true,
              onSelected: (id) => picked = id,
              onPreviewTheme: (_) async =>
                  const ThemePreviewResult.theme(QueryaTheme.darkDefault),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Querya Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Querya Light'));
      await tester.pumpAndSettle();

      expect(picked, ThemeController.builtinQueryaLightId);
    });
  });

  group('filterThemeDefinitions metadata', () {
    test('matches author and tags', () {
      final themes = [
        const ThemeDefinition(
          id: 'neon',
          name: 'Neon Nights',
          source: ThemeSource.filesystem,
          format: ThemeFormat.queryaCustom,
          isDark: true,
          metadata: ThemeMetadata(
            author: 'Querya Themes',
            tags: ['cyberpunk', 'dark'],
          ),
        ),
      ];

      expect(filterThemeDefinitions(themes, 'querya themes'), hasLength(1));
      expect(filterThemeDefinitions(themes, 'cyber'), hasLength(1));
      expect(filterThemeDefinitions(themes, 'light'), isEmpty);
    });
  });
}
