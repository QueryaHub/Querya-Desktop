import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';
import 'package:querya_desktop/features/main_screen/querya_window_title_bar.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

const _customCanvas = Color(0xFF112233);
const _customSurface = Color(0xFF445566);
const _customMuted = Color(0xFF99AABB);

QueryaTheme _themeWithWorkbench(QueryaWorkbenchTheme workbench) {
  return QueryaTheme.darkDefault.copyWith(workbench: workbench);
}

void main() {
  testWidgets('title bar background follows workbench canvas', (tester) async {
    late Color background;

    await tester.pumpWidget(
      queryaThemeTestShell(
        data: _themeWithWorkbench(
          QueryaWorkbenchTheme.darkDefault.copyWith(canvas: _customCanvas),
        ),
        child: material.Builder(
          builder: (context) {
            background = QueryaWindowTitleBar.titleBarBackground(context);
            return const material.SizedBox();
          },
        ),
      ),
    );

    expect(background, _customCanvas);
  });

  testWidgets('window button colors use workbench surface and mutedForeground',
      (tester) async {
    late WindowButtonColors colors;

    await tester.pumpWidget(
      queryaThemeTestShell(
        data: _themeWithWorkbench(
          QueryaWorkbenchTheme.darkDefault.copyWith(
            surface: _customSurface,
            mutedForeground: _customMuted,
          ),
        ),
        child: material.Builder(
          builder: (context) {
            colors = QueryaWindowTitleBar.windowButtonColors(context);
            return const material.SizedBox();
          },
        ),
      ),
    );

    expect(colors.iconNormal, _customMuted);
    expect(colors.mouseOver, _customSurface.withValues(alpha: 0.85));
  });

  testWidgets('chrome style updates when QueryaThemeScope workbench changes',
      (tester) async {
    late Color background;

    await tester.pumpWidget(
      queryaThemeTestShell(
        data: _themeWithWorkbench(
          QueryaWorkbenchTheme.darkDefault.copyWith(canvas: _customCanvas),
        ),
        child: material.Builder(
          builder: (context) {
            background = QueryaWindowTitleBar.titleBarBackground(context);
            return const material.SizedBox();
          },
        ),
      ),
    );
    expect(background, _customCanvas);

    await tester.pumpWidget(
      queryaThemeTestShell(
        data: _themeWithWorkbench(
          QueryaWorkbenchTheme.lightDefault.copyWith(canvas: _customSurface),
        ),
        child: material.Builder(
          builder: (context) {
            background = QueryaWindowTitleBar.titleBarBackground(context);
            return const material.SizedBox();
          },
        ),
      ),
    );
    expect(background, _customSurface);
  });

  testWidgets('title bar leading inset reserves macOS traffic-light space',
      (tester) async {
    expect(
      QueryaWindowTitleBar.titleBarLeadingInset(
        isMacOS: true,
        scale: (v) => v,
      ),
      72,
    );
    expect(
      QueryaWindowTitleBar.titleBarLeadingInset(
        isMacOS: false,
        scale: (v) => v,
      ),
      16,
    );
  });

  test('bitsdojo window buttons hidden on macOS, shown elsewhere', () {
    expect(
      QueryaWindowTitleBar.showBitsdojoWindowButtons(isMacOS: true),
      isFalse,
    );
    expect(
      QueryaWindowTitleBar.showBitsdojoWindowButtons(isMacOS: false),
      isTrue,
    );
  });

  testWidgets('read-only state is persistently visible in title bar',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.SizedBox(
          width: 1000,
          child: QueryaReadOnlyBadge(),
        ),
      ),
    );

    expect(
      find.byKey(const Key('title_bar_read_only_badge')),
      findsOneWidget,
    );
    expect(find.text('Read-only'), findsWidgets);
  });
}
