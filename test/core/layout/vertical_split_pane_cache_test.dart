import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/layout/vertical_split_pane.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets(
      'a width-only surface resize does not rebuild the split body; a height change does',
      (tester) async {
    final fraction = material.ValueNotifier<double>(0.5);
    addTearDown(fraction.dispose);

    await tester.binding.setSurfaceSize(const material.Size(800, 400));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox.expand(
          child: VerticalSplitPane(
            fraction: fraction,
            top: const material.ColoredBox(color: material.Colors.red),
            bottom: const material.ColoredBox(color: material.Colors.blue),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final afterFirst = verticalSplitPaneBodyBuildCount;
    expect(afterFirst, greaterThanOrEqualTo(1));

    // Width-only surface resizes (same height): must not rebuild the body —
    // this is exactly what an ancestor sidebar-width animation looks like
    // from this pane's perspective (#984).
    await tester.binding.setSurfaceSize(const material.Size(600, 400));
    await tester.pump();
    await tester.binding.setSurfaceSize(const material.Size(400, 400));
    await tester.pump();
    expect(verticalSplitPaneBodyBuildCount, afterFirst);

    // A real height change must rebuild it.
    await tester.binding.setSurfaceSize(const material.Size(400, 300));
    await tester.pump();
    expect(verticalSplitPaneBodyBuildCount, greaterThan(afterFirst));

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
      'changing top/bottom content rebuilds the split body even at the same height',
      (tester) async {
    final fraction = material.ValueNotifier<double>(0.5);
    addTearDown(fraction.dispose);

    Future<void> pumpWith(material.Widget top) => tester.pumpWidget(
          queryaThemeTestShell(
            child: material.SizedBox(
              width: 800,
              height: 400,
              child: VerticalSplitPane(
                fraction: fraction,
                top: top,
                bottom: const material.ColoredBox(color: material.Colors.blue),
              ),
            ),
          ),
        );

    await pumpWith(const material.ColoredBox(color: material.Colors.red));
    await tester.pumpAndSettle();
    final afterFirst = verticalSplitPaneBodyBuildCount;

    await pumpWith(const material.ColoredBox(color: material.Colors.green));
    await tester.pumpAndSettle();

    expect(verticalSplitPaneBodyBuildCount, greaterThan(afterFirst));
  });
}
