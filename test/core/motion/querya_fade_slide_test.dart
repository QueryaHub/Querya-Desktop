import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_fade_slide.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';

void main() {
  Widget wrap(
    Widget child, {
    QueryaMotionLevel level = QueryaMotionLevel.full,
  }) {
    return MaterialApp(
      home: QueryaMotionScope(
        level: level,
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('switches keyed children through AnimatedSwitcher', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaFadeSlide(
          child: Text('one', key: ValueKey('one')),
        ),
      ),
    );
    expect(find.text('one'), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        const QueryaFadeSlide(
          child: Text('two', key: ValueKey('two')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('two'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('keeps outgoing child briefly during transition', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaFadeSlide(
          child: Text('one', key: ValueKey('one')),
        ),
      ),
    );
    await tester.pumpWidget(
      wrap(
        const QueryaFadeSlide(
          child: Text('two', key: ValueKey('two')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
  });

  testWidgets('instant when motion off', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaFadeSlide(
          child: Text('a', key: ValueKey('a')),
        ),
        level: QueryaMotionLevel.off,
      ),
    );

    final switcher =
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(switcher.duration, QueryaMotion.instant);

    await tester.pumpWidget(
      wrap(
        const QueryaFadeSlide(
          child: Text('b', key: ValueKey('b')),
        ),
        level: QueryaMotionLevel.off,
      ),
    );
    await tester.pump();
    expect(find.text('b'), findsOneWidget);
    expect(find.text('a'), findsNothing);
  });

  testWidgets('uses standard/enter duration tokens (full motion)',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaFadeSlide(
          child: Text('x', key: ValueKey('x')),
        ),
      ),
    );
    final switcher =
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(switcher.duration, QueryaMotion.standard);
    expect(switcher.switchInCurve, QueryaMotion.enter);
  });

  testWidgets('halves standard duration when reduced', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaFadeSlide(
          child: Text('x', key: ValueKey('x')),
        ),
        level: QueryaMotionLevel.reduced,
      ),
    );
    final switcher =
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(
      switcher.duration,
      QueryaMotion.effectiveDuration(
        tester.element(find.byType(QueryaFadeSlide)),
        QueryaMotion.standard,
      ),
    );
    expect(switcher.switchInCurve, QueryaMotion.enter);
  });

  testWidgets('instant when OS disables animations', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: QueryaMotionScope(
            level: QueryaMotionLevel.full,
            child: Scaffold(
              body: Center(
                child: QueryaFadeSlide(
                  child: Text('x', key: ValueKey('x')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final switcher =
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(switcher.duration, QueryaMotion.instant);
  });

  testWidgets('same key does not rebuild as a switch', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaFadeSlide(
          child: Text('same', key: ValueKey('k')),
        ),
      ),
    );
    await tester.pumpWidget(
      wrap(
        const QueryaFadeSlide(
          child: Text('same', key: ValueKey('k')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('same'), findsOneWidget);
    expect(find.byType(FadeTransition), findsWidgets);
  });
}
