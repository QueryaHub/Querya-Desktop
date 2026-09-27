import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/lazy_offstage.dart';

/// #984: while [LazyOffstage.offstage] is true, the hidden child must keep
/// its last known size even if a sibling's size change (e.g. the sidebar
/// toggle animation resizing the workspace next to it) feeds it new
/// constraints every frame. Once it's made visible again, it must be laid
/// out for real against whatever the constraints are *at that point*,
/// never a stale value from while it was hidden.
void main() {
  Future<double> capturedWidth(
    WidgetTester tester, {
    required double siblingWidth,
    required bool hidden,
  }) async {
    late double captured;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 50,
            child: Row(
              children: [
                SizedBox(width: siblingWidth),
                Expanded(
                  child: LazyOffstage(
                    offstage: hidden,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        captured = constraints.maxWidth;
                        return const SizedBox.expand();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets(
      'keeps the stale width while hidden despite constraint changes, '
      'then relays out with the fresh width once shown again',
      (tester) async {
    // Initial layout (never laid out before): 400 - 100 = 300.
    final initial =
        await capturedWidth(tester, siblingWidth: 100, hidden: true);
    expect(initial, 300);

    // Sibling grows while still hidden: a plain Offstage would forward this
    // straight through (captured -> 150); LazyOffstage must not.
    final whileHidden =
        await capturedWidth(tester, siblingWidth: 250, hidden: true);
    expect(whileHidden, 300);

    // Made visible again: must now reflect the current constraints (150),
    // not the stale 300 from while it was hidden.
    final whenShown =
        await capturedWidth(tester, siblingWidth: 250, hidden: false);
    expect(whenShown, 150);
  });
}
