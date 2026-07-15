import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/layout/querya_split_handle.dart';
import 'package:querya_desktop/core/layout/vertical_split_pane.dart';

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
}
