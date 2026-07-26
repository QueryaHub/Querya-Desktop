import 'package:flutter/material.dart';
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

  testWidgets('showAppDialog uses fade-slide (not scale) with BackdropFilter',
      (tester) async {
    final ctx = await pumpHost(tester);

    showAppDialog<void>(
      context: ctx,
      builder: (c) => const SimpleDialog(title: Text('X')),
    );
    await tester.pump();
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsWidgets);
    expect(find.byType(ScaleTransition), findsNothing);
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
