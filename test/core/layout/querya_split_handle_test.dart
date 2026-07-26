import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/layout/querya_split_handle.dart';
import 'package:querya_desktop/core/layout/vertical_split_pane.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('vertical split keeps drag and supports keyboard and semantics',
      (tester) async {
    final fraction = material.ValueNotifier(0.5);
    addTearDown(fraction.dispose);

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 600,
          height: 400,
          child: VerticalSplitPane(
            fraction: fraction,
            handleKey: const material.Key('handle'),
            top: const material.SizedBox.expand(),
            bottom: const material.SizedBox.expand(),
          ),
        ),
      ),
    );

    final handle = find.byKey(const material.Key('handle'));
    final semantics = tester.getSemantics(
      find.bySemanticsLabel('Resize query and output panes'),
    );
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue);
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue);

    await tester.tap(handle);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(fraction.value, greaterThan(0.5));

    final afterKeyboard = fraction.value;
    await tester.drag(handle, const material.Offset(0, -40));
    await tester.pump();
    expect(fraction.value, lessThan(afterKeyboard));
  });

  testWidgets('horizontal split handle responds to Left and Right',
      (tester) async {
    var totalDelta = 0.0;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: material.Row(
            children: [
              const material.Expanded(child: material.SizedBox()),
              QueryaSplitHandle(
                axis: material.Axis.horizontal,
                semanticsLabel: 'Resize connections and workspace panes',
                onDragDelta: (delta) => totalDelta += delta,
              ),
              const material.Expanded(child: material.SizedBox()),
            ],
          ),
        ),
      ),
    );

    final handle = find.bySemanticsLabel(
      'Resize connections and workspace panes',
    );
    await tester.tap(handle);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(totalDelta, 10);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(totalDelta, 0);
  });

  testWidgets('focus ring uses motion-aware AnimatedContainer', (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: material.SizedBox(
            width: 200,
            height: 200,
            child: QueryaSplitHandle(
              axis: material.Axis.horizontal,
              semanticsLabel: 'Resize',
              onDragDelta: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final animated = tester.widget<material.AnimatedContainer>(
      find.byType(material.AnimatedContainer),
    );
    expect(animated.duration, QueryaMotion.fast);

    await tester.tap(find.bySemanticsLabel('Resize'));
    await tester.pump();
    final focused = tester.widget<material.AnimatedContainer>(
      find.byType(material.AnimatedContainer),
    );
    final border = focused.decoration! as material.BoxDecoration;
    expect(
      (border.border! as material.Border).top.color,
      isNot(material.Colors.transparent),
    );
  });

  testWidgets('vertical drag-end settle can overshoot then rest (full motion)',
      (tester) async {
    final fraction = material.ValueNotifier(0.5);
    addTearDown(fraction.dispose);

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: material.SizedBox(
            width: 600,
            height: 400,
            child: VerticalSplitPane(
              fraction: fraction,
              handleKey: const material.Key('handle'),
              top: const material.SizedBox.expand(),
              bottom: const material.SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final handle = find.byKey(const material.Key('handle'));
    // Fling downward to impart release velocity.
    await tester.fling(handle, const material.Offset(0, 80), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    // Mid-settle may leave the release point.
    final mid = fraction.value;
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(fraction.value, inInclusiveRange(0.2, 0.8));
    // Either settled near mid or returned after overshoot — must be finite.
    expect(fraction.value.isFinite, isTrue);
    expect(mid.isFinite, isTrue);
  });

  testWidgets('motion off skips settle spring on drag end', (tester) async {
    final fraction = material.ValueNotifier(0.5);
    addTearDown(fraction.dispose);

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.off,
          child: material.SizedBox(
            width: 600,
            height: 400,
            child: VerticalSplitPane(
              fraction: fraction,
              handleKey: const material.Key('handle'),
              top: const material.SizedBox.expand(),
              bottom: const material.SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final handle = find.byKey(const material.Key('handle'));
    await tester.drag(handle, const material.Offset(0, 40));
    await tester.pump();
    final afterDrag = fraction.value;
    await tester.pump(const Duration(milliseconds: 100));
    expect(fraction.value, afterDrag);
  });
}
