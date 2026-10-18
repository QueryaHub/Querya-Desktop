import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/theme/animated_querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';

void main() {
  testWidgets('snaps when duration is zero', (tester) async {
    await tester.pumpWidget(
      AnimatedQueryaTheme(
        data: QueryaTheme.darkDefault,
        duration: QueryaMotion.instant,
        child: Builder(
          builder: (context) {
            return ColoredBox(
              color: context.queryaTheme.colors.background,
              child: const SizedBox(width: 10, height: 10),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(
      contextBackground(tester),
      QueryaTheme.darkDefault.colors.background,
    );

    await tester.pumpWidget(
      AnimatedQueryaTheme(
        data: QueryaTheme.lightDefault,
        duration: QueryaMotion.instant,
        child: Builder(
          builder: (context) {
            return ColoredBox(
              color: context.queryaTheme.colors.background,
              child: const SizedBox(width: 10, height: 10),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(
      contextBackground(tester),
      QueryaTheme.lightDefault.colors.background,
    );
  });

  testWidgets('lerps mid-flight then settles', (tester) async {
    await tester.pumpWidget(
      AnimatedQueryaTheme(
        data: QueryaTheme.darkDefault,
        duration: QueryaMotion.slow,
        curve: QueryaMotion.emphasized,
        child: Builder(
          builder: (context) {
            return ColoredBox(
              key: const Key('swatch'),
              color: context.queryaTheme.colors.background,
              child: const SizedBox(width: 10, height: 10),
            );
          },
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      AnimatedQueryaTheme(
        data: QueryaTheme.lightDefault,
        duration: QueryaMotion.slow,
        curve: QueryaMotion.emphasized,
        child: Builder(
          builder: (context) {
            return ColoredBox(
              key: const Key('swatch'),
              color: context.queryaTheme.colors.background,
              child: const SizedBox(width: 10, height: 10),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final mid = contextBackground(tester);
    expect(mid, isNot(QueryaTheme.darkDefault.colors.background));
    expect(mid, isNot(QueryaTheme.lightDefault.colors.background));

    await tester.pumpAndSettle();
    expect(
      contextBackground(tester),
      QueryaTheme.lightDefault.colors.background,
    );
  });

  test('QueryaThemeTween lerps via QueryaTheme.lerp', () {
    final tween = QueryaThemeTween(
      begin: QueryaTheme.darkDefault,
      end: QueryaTheme.lightDefault,
    );
    final mid = tween.lerp(0.5);
    expect(
      mid.colors.background,
      Color.lerp(
        QueryaTheme.darkDefault.colors.background,
        QueryaTheme.lightDefault.colors.background,
        0.5,
      ),
    );
  });
}

Color contextBackground(WidgetTester tester) {
  final box = tester.widget<ColoredBox>(find.byType(ColoredBox));
  return box.color;
}
