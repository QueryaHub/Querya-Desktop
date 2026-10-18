import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/theme/querya_ui_colors.dart';

import '../../support/querya_theme_test_shell.dart';

/// QueryaUiColors interpolation and `context.colors` lookup (#1730, #1735).
void main() {
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
          data: QueryaTheme.lightDefault,
          child: material.Builder(builder: (context) {
            seen = context.colors;
            return const material.SizedBox.shrink();
          }),
        ),
      ));
      expect(seen, QueryaTheme.lightDefault.colors);
    });
  });
}
