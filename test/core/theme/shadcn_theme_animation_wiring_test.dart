import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

void main() {
  Widget wrap(Widget child) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );
  }

  testWidgets('ShadcnLayer disables AnimatedTheme when enableThemeAnimation false',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        shadcn.ShadcnLayer(
          theme: shadcn.ThemeData.dark(),
          enableThemeAnimation: false,
          child: const SizedBox(width: 8, height: 8),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(shadcn.AnimatedTheme), findsNothing);
  });

  testWidgets('ShadcnLayer uses provided duration and curve', (tester) async {
    await tester.pumpWidget(
      wrap(
        shadcn.ShadcnLayer(
          theme: shadcn.ThemeData.dark(),
          enableThemeAnimation: true,
          themeAnimationDuration: QueryaMotion.slow,
          themeAnimationCurve: QueryaMotion.emphasized,
          child: const SizedBox(width: 8, height: 8),
        ),
      ),
    );
    await tester.pump();
    final animated =
        tester.widget<shadcn.AnimatedTheme>(find.byType(shadcn.AnimatedTheme));
    expect(animated.duration, QueryaMotion.slow);
    expect(animated.curve, QueryaMotion.emphasized);
  });
}
