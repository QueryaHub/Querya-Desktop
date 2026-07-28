import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_cross_fade_stack.dart';

void main() {
  testWidgets('QueryaCrossFadeStack cross-fades children and excludes focus',
      (WidgetTester tester) async {
    final focusNode1 = FocusNode();
    final focusNode2 = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QueryaCrossFadeStack(
            index: 0,
            children: [
              TextField(
                key: const Key('input_active'),
                focusNode: focusNode1,
              ),
              TextField(
                key: const Key('input_hidden'),
                focusNode: focusNode2,
              ),
            ],
          ),
        ),
      ),
    );

    // 1. Verify index 0 is visible (opacity 1.0) and index 1 is invisible (opacity 0.0)
    final animatedOpacityFinder = find.byType(AnimatedOpacity);
    expect(animatedOpacityFinder, findsNWidgets(2));

    final opacity1 =
        tester.widget<AnimatedOpacity>(animatedOpacityFinder.at(0)).opacity;
    final opacity2 =
        tester.widget<AnimatedOpacity>(animatedOpacityFinder.at(1)).opacity;
    expect(opacity1, 1.0);
    expect(opacity2, 0.0);

    // 2. Focus the active TextField
    focusNode1.requestFocus();
    await tester.pump();
    expect(focusNode1.hasFocus, isTrue);

    // 3. Attempt to focus the hidden TextField
    focusNode2.requestFocus();
    await tester.pump();
    // It should NOT have focus because it is wrapped in ExcludeFocus(excluding: true)
    expect(focusNode2.hasFocus, isFalse);

    // Cleanup
    focusNode1.dispose();
    focusNode2.dispose();
  });

  testWidgets('QueryaCrossFadeStack clamps out-of-range index',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QueryaCrossFadeStack(
            index: 99,
            children: [
              Text('only', key: Key('only_child')),
            ],
          ),
        ),
      ),
    );

    final opacity =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 1.0);
    expect(find.byKey(const Key('only_child')), findsOneWidget);
  });

  testWidgets('QueryaCrossFadeStack uses exit curve when fading out',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QueryaCrossFadeStack(
            index: 0,
            children: const [
              Text('a', key: Key('a')),
              Text('b', key: Key('b')),
            ],
          ),
        ),
      ),
    );

    final opacities =
        tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacities.elementAt(0).opacity, 1.0);
    expect(opacities.elementAt(1).opacity, 0.0);
    // Inactive layer uses exit curve; active uses enter.
    expect(opacities.elementAt(0).curve, isNot(opacities.elementAt(1).curve));
  });
}
