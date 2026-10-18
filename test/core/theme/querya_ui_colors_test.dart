import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_from_vscode.dart';
import 'package:querya_desktop/core/theme/querya_color_scheme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/theme/querya_ui_colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn
    hide Gap, TextExtension;

import '../../support/querya_theme_test_shell.dart';

/// QueryaUiColors gives the colours the shadcn scheme gives today (#1730).
void main() {
  final imported = buildQueryaThemeFromVsCodeColors(
    brightness: shadcn.Brightness.dark,
    colors: const {
      'editor.background': '#1e1e2e',
      'focusBorder': '#f38ba8',
      'errorForeground': '#ff5555',
    },
    fallback: QueryaTheme.darkDefault,
  );
  final themes = {
    'dark': QueryaTheme.darkDefault,
    'light': QueryaTheme.lightDefault,
    'imported': imported,
  };

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    test('$name: every field equals the shadcn scheme field', () {
      final s = theme.colorScheme;
      final c = theme.colors;
      expect(c.brightness, s.brightness);
      expect(c.background, s.background);
      expect(c.foreground, s.foreground);
      expect(c.card, s.card);
      expect(c.popover, s.popover);
      expect(c.popoverForeground, s.popoverForeground);
      expect(c.primary, s.primary);
      expect(c.primaryForeground, s.primaryForeground);
      expect(c.secondary, s.secondary);
      expect(c.secondaryForeground, s.secondaryForeground);
      expect(c.muted, s.muted);
      expect(c.mutedForeground, s.mutedForeground);
      expect(c.accent, s.accent);
      expect(c.destructive, s.destructive);
      expect(c.destructiveForeground, s.destructiveForeground);
      expect(c.border, s.border);
      expect(c.ring, s.ring);
      expect([c.chart1, c.chart2, c.chart3, c.chart4, c.chart5],
          [s.chart1, s.chart2, s.chart3, s.chart4, s.chart5]);
    });

    test('$name: back to a shadcn scheme it is the same scheme', () {
      final s = theme.colorScheme;
      final back = theme.colors.toShadcn();
      expect(back.uiColors, theme.colors);
      // The fields the app does not read follow their neighbours, as every
      // Querya theme sets them.
      expect(back.cardForeground, s.cardForeground);
      expect(back.accentForeground, s.accentForeground);
      expect(back.input, s.input);
    });
  }

  test('one scheme instance gives one QueryaUiColors', () {
    final s = QueryaTheme.darkDefault.colorScheme;
    expect(identical(s.uiColors, s.uiColors), isTrue);
  });

  test('lerp: the ends are the themes, the middle is between', () {
    final a = QueryaTheme.darkDefault.colors;
    final b = QueryaTheme.lightDefault.colors;
    expect(QueryaUiColors.lerp(a, b, 0), a);
    expect(QueryaUiColors.lerp(a, b, 1), b);
    final mid = QueryaUiColors.lerp(a, b, 0.5);
    expect(mid.background, material.Color.lerp(a.background, b.background, 0.5));
    expect(mid.brightness, b.brightness);
  });

  group('context.colors', () {
    testWidgets('under the shell: the shell theme\'s colours', (tester) async {
      late QueryaUiColors seen;
      await tester.pumpWidget(queryaThemeTestShell(
        data: QueryaTheme.lightDefault,
        child: material.Builder(builder: (context) {
          seen = context.colors;
          return const material.SizedBox.shrink();
        }),
      ));
      expect(seen, QueryaTheme.lightDefault.colors);
    });

    testWidgets('a bare app: the default theme of its brightness',
        (tester) async {
      late QueryaUiColors seen;
      await tester.pumpWidget(material.MaterialApp(
        theme: material.ThemeData(brightness: material.Brightness.light),
        home: material.Builder(builder: (context) {
          seen = context.colors;
          return const material.SizedBox.shrink();
        }),
      ));
      expect(seen, QueryaTheme.lightDefault.colors);
    });

    testWidgets('a scope without the shell: the scope\'s colours',
        (tester) async {
      late QueryaUiColors seen;
      await tester.pumpWidget(material.MaterialApp(
        home: QueryaThemeScope(
          data: imported,
          child: material.Builder(builder: (context) {
            seen = context.colors;
            return const material.SizedBox.shrink();
          }),
        ),
      ));
      expect(seen, imported.colors);
    });
  });
}
