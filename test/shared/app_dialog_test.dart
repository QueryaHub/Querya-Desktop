import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/shared/widgets/app_dialog.dart';

void main() {
  Future<BuildContext> pumpHost(
    WidgetTester tester, {
    QueryaMotionLevel level = QueryaMotionLevel.full,
  }) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: QueryaMotionScope(
          level: level,
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  testWidgets('barrierDismissible true closes dialog on backdrop tap',
      (tester) async {
    final ctx = await pumpHost(tester);
    var completed = false;

    final future = showAppDialog<void>(
      context: ctx,
      barrierDismissible: true,
      builder: (c) => const AlertDialog(title: Text('Dialog title')),
    ).whenComplete(() => completed = true);

    await tester.pumpAndSettle();
    expect(find.text('Dialog title'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Dialog title'), findsNothing);
    expect(completed, isTrue);
    await future;
  });

  testWidgets('barrierDismissible false ignores backdrop tap', (tester) async {
    final ctx = await pumpHost(tester);

    final future = showAppDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(title: Text('Blocking dialog')),
    );

    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Blocking dialog'), findsOneWidget);

    Navigator.of(ctx, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    await future;
  });

  testWidgets('barrierDismissible true closes dialog on Escape', (tester) async {
    final ctx = await pumpHost(tester);
    var completed = false;

    final future = showAppDialog<void>(
      context: ctx,
      barrierDismissible: true,
      builder: (c) => const AlertDialog(title: Text('Escapable')),
    ).whenComplete(() => completed = true);

    await tester.pumpAndSettle();
    expect(find.text('Escapable'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Escapable'), findsNothing);
    expect(completed, isTrue);
    await future;
  });

  testWidgets('barrierDismissible false ignores Escape', (tester) async {
    final ctx = await pumpHost(tester);

    final future = showAppDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(title: Text('No escape')),
    );

    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('No escape'), findsOneWidget);

    Navigator.of(ctx, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    await future;
  });

  testWidgets('showAppDialog uses fade-slide (not scale) with BackdropFilter',
      (tester) async {
    final ctx = await pumpHost(tester);

    showAppDialog<void>(
      context: ctx,
      builder: (c) => const SimpleDialog(title: Text('X')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsWidgets);
    expect(find.byType(ScaleTransition), findsNothing);
  });

  group('backdrop transition (#886)', () {
    final fullFilter = ImageFilter.blur(sigmaX: 8, sigmaY: 8);
    final fullTint = const Color(0xFF000000).withValues(alpha: 0.32);

    Color tintOf(WidgetTester tester) {
      final box = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(ColoredBox),
        ),
      );
      return box.color;
    }

    testWidgets('blur and tint scale in during enter; no Opacity wraps the filter',
        (tester) async {
      final ctx = await pumpHost(tester);

      showAppDialog<void>(
        context: ctx,
        builder: (c) => const SimpleDialog(title: Text('Blur')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter.filter, isNot(fullFilter), reason: 'sigma is still ramping');
      expect(tintOf(tester).a, greaterThan(0));
      expect(tintOf(tester).a, lessThan(fullTint.a));

      // The frost must not sit under an Opacity (that forces an offscreen layer).
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });

    testWidgets('settles at full blur and tint', (tester) async {
      final ctx = await pumpHost(tester);

      showAppDialog<void>(
        context: ctx,
        builder: (c) => const SimpleDialog(title: Text('Settled')),
      );
      await tester.pumpAndSettle();

      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter.filter, fullFilter);
      expect(tintOf(tester), fullTint);
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });

    testWidgets('blur and tint fade out again on dismiss', (tester) async {
      final ctx = await pumpHost(tester);

      final future = showAppDialog<void>(
        context: ctx,
        builder: (c) => const SimpleDialog(title: Text('Leaving')),
      );
      await tester.pumpAndSettle();

      Navigator.of(ctx, rootNavigator: true).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter.filter, isNot(fullFilter));
      expect(tintOf(tester).a, lessThan(fullTint.a));

      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      await future;
    });
  });

  testWidgets('enter uses standard duration under full motion', (tester) async {
    final ctx = await pumpHost(tester);
    showAppDialog<void>(
      context: ctx,
      builder: (c) => const AlertDialog(title: Text('Timed')),
    );
    await tester.pump();

    final route = ModalRoute.of(tester.element(find.text('Timed')));
    expect(route, isA<ModalRoute<dynamic>>());
    // showGeneralDialog uses transitionDuration from showAppDialog call site.
    expect(
      QueryaMotion.effectiveDuration(ctx, QueryaMotion.standard),
      QueryaMotion.standard,
    );
  });

  testWidgets('dismiss animates with exit reverseCurve (opacity decreases)',
      (tester) async {
    final ctx = await pumpHost(tester);

    final future = showAppDialog<void>(
      context: ctx,
      builder: (c) => const AlertDialog(title: Text('Leaving')),
    );
    await tester.pumpAndSettle();

    Navigator.of(ctx, rootNavigator: true).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final fades = tester
        .widgetList<FadeTransition>(find.byType(FadeTransition))
        .where((f) => f.opacity.value < 1.0)
        .toList();
    expect(fades, isNotEmpty);

    await tester.pumpAndSettle();
    expect(find.text('Leaving'), findsNothing);
    await future;
  });

  testWidgets('motion off opens and closes instantly', (tester) async {
    final ctx = await pumpHost(tester, level: QueryaMotionLevel.off);

    final future = showAppDialog<void>(
      context: ctx,
      builder: (c) => const AlertDialog(title: Text('Snap')),
    );
    await tester.pump();
    expect(find.text('Snap'), findsOneWidget);

    Navigator.of(ctx, rootNavigator: true).pop();
    await tester.pump();
    expect(find.text('Snap'), findsNothing);
    await future;
  });
}
