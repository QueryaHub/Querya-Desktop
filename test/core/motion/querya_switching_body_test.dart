import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/motion/querya_switching_body.dart';

void main() {
  Widget wrap(
    Widget child, {
    QueryaMotionLevel level = QueryaMotionLevel.full,
  }) {
    return MaterialApp(
      home: QueryaMotionScope(
        level: level,
        child: Scaffold(body: child),
      ),
    );
  }

  testWidgets('keeps inactive child mounted and excludes focus', (tester) async {
    final focusA = FocusNode();
    final focusB = FocusNode();
    addTearDown(focusA.dispose);
    addTearDown(focusB.dispose);

    await tester.pumpWidget(
      wrap(
        QueryaSwitchingBody(
          index: 0,
          children: [
            TextField(key: const Key('a'), focusNode: focusA),
            TextField(key: const Key('b'), focusNode: focusB),
          ],
        ),
      ),
    );

    expect(find.byKey(const Key('a')), findsOneWidget);
    // Inactive child b is kept mounted (skipOffstage: false) but offstaged (skipOffstage: true).
    expect(find.byKey(const Key('b'), skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('b')), findsNothing);

    focusB.requestFocus();
    await tester.pump();
    expect(focusB.hasFocus, isFalse);

    await tester.pumpWidget(
      wrap(
        QueryaSwitchingBody(
          index: 1,
          children: [
            TextField(key: const Key('a'), focusNode: focusA),
            TextField(key: const Key('b'), focusNode: focusB),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('b')), findsOneWidget);
    expect(find.byKey(const Key('a'), skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('a')), findsNothing);

    focusB.requestFocus();
    await tester.pump();
    expect(focusB.hasFocus, isTrue);
  });

  testWidgets('preserves StatefulWidget state across index switches',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          children: [
            _CounterPane(key: Key('pane-a'), label: 'A'),
            _CounterPane(key: Key('pane-b'), label: 'B'),
          ],
        ),
      ),
    );

    await tester.tap(find.text('A:0'));
    await tester.pump();
    expect(find.text('A:1'), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 1,
          children: [
            _CounterPane(key: Key('pane-a'), label: 'A'),
            _CounterPane(key: Key('pane-b'), label: 'B'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('B:0'), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          children: [
            _CounterPane(key: Key('pane-a'), label: 'A'),
            _CounterPane(key: Key('pane-b'), label: 'B'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A:1'), findsOneWidget);
  });

  testWidgets('inactive layer ignores pointer events', (tester) async {
    var tapsA = 0;
    var tapsB = 0;

    await tester.pumpWidget(
      wrap(
        QueryaSwitchingBody(
          index: 0,
          children: [
            GestureDetector(
              key: const Key('a'),
              onTap: () => tapsA++,
              child: const SizedBox.expand(child: ColoredBox(color: Colors.red)),
            ),
            GestureDetector(
              key: const Key('b'),
              onTap: () => tapsB++,
              child:
                  const SizedBox.expand(child: ColoredBox(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('a')));
    expect(tapsA, 1);
    expect(tapsB, 0);

    // Center still hits active layer only.
    await tester.tapAt(tester.getCenter(find.byType(QueryaSwitchingBody)));
    expect(tapsA, 2);
    expect(tapsB, 0);
  });

  testWidgets('clamps out-of-range index', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 99,
          children: [
            Text('only', key: Key('only')),
            Text('other', key: Key('other')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final opacities = tester.widgetList<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(opacities.length, 2);
    expect(opacities.last.opacity, 1.0);
    expect(opacities.first.opacity, 0.0);
  });

  testWidgets('uses AnimatedSlide when slide is non-zero', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          slide: Offset(0.02, 0),
          children: [
            Text('a'),
            Text('b'),
          ],
        ),
      ),
    );
    expect(find.byType(AnimatedSlide), findsNWidgets(2));
  });

  testWidgets('skips AnimatedSlide when slide is zero', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          slide: Offset.zero,
          children: [
            Text('a'),
            Text('b'),
          ],
        ),
      ),
    );
    expect(find.byType(AnimatedSlide), findsNothing);
    expect(find.byType(AnimatedOpacity), findsNWidgets(2));
  });

  testWidgets('full motion uses standard duration', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          children: [Text('a'), Text('b')],
        ),
      ),
    );
    final opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity).first,
    );
    expect(opacity.duration, QueryaMotion.standard);
  });

  testWidgets('motion off uses instant duration', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          children: [Text('a'), Text('b')],
        ),
        level: QueryaMotionLevel.off,
      ),
    );
    final opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity).first,
    );
    expect(opacity.duration, QueryaMotion.instant);
  });

  testWidgets('halves standard duration when reduced', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          children: [Text('a'), Text('b')],
        ),
        level: QueryaMotionLevel.reduced,
      ),
    );
    final opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity).first,
    );
    expect(
      opacity.duration,
      QueryaMotion.effectiveDuration(
        tester.element(find.byType(QueryaSwitchingBody)),
        QueryaMotion.standard,
      ),
    );
  });

  testWidgets('inactive layer disables TickerMode and uses RepaintBoundary',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          children: [
            Text('active'),
            Text('inactive'),
          ],
        ),
      ),
    );

    final tickers = tester
        .widgetList<TickerMode>(
          find.descendant(
            of: find.byType(QueryaSwitchingBody),
            matching: find.byType(TickerMode),
          ),
        )
        .toList();
    expect(tickers.length, 2);
    expect(tickers.first.enabled, isTrue);
    expect(tickers.last.enabled, isFalse);

    expect(
      find.descendant(
        of: find.byType(QueryaSwitchingBody),
        matching: find.byType(RepaintBoundary),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('ExcludeSemantics excludes inactive child', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          children: [
            Text('active'),
            Text('inactive'),
          ],
        ),
      ),
    );

    final excludes = tester
        .widgetList<ExcludeSemantics>(
          find.descendant(
            of: find.byType(QueryaSwitchingBody),
            matching: find.byType(ExcludeSemantics),
          ),
        )
        .toList();
    expect(excludes.length, 2);
    expect(excludes.first.excluding, isFalse);
    expect(excludes.last.excluding, isTrue);
  });

  testWidgets(
      'inactive layer remains onstage during exit transition and offstages on completion',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          children: [
            Text('pane-0', key: Key('pane-0')),
            Text('pane-1', key: Key('pane-1')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initially pane-0 is onstage, pane-1 is offstage
    expect(find.byKey(const Key('pane-0')), findsOneWidget);
    expect(find.byKey(const Key('pane-1')), findsNothing);
    expect(find.byKey(const Key('pane-1'), skipOffstage: false), findsOneWidget);

    // Switch to index 1
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 1,
          children: [
            Text('pane-0', key: Key('pane-0')),
            Text('pane-1', key: Key('pane-1')),
          ],
        ),
      ),
    );

    // Advance halfway through exit animation (e.g. 50ms)
    await tester.pump(const Duration(milliseconds: 50));

    // Both panes must be onstage during transition
    expect(find.byKey(const Key('pane-0')), findsOneWidget);
    expect(find.byKey(const Key('pane-1')), findsOneWidget);

    // Settle transition
    await tester.pumpAndSettle();

    // Now pane-0 is offstaged, pane-1 is active
    expect(find.byKey(const Key('pane-0')), findsNothing);
    expect(find.byKey(const Key('pane-0'), skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('pane-1')), findsOneWidget);
  });

  testWidgets(
      'inactive layer configures Offstage(offstage: true) once exit transition completes',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 0,
          children: [
            Text('A', key: Key('child-a')),
            Text('B', key: Key('child-b')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final offstageFinder = find.descendant(
      of: find.byType(QueryaSwitchingBody),
      matching: find.byType(Offstage, skipOffstage: false),
    );

    final offstagesInitial = tester.widgetList<Offstage>(offstageFinder).toList();
    expect(offstagesInitial.length, 2);
    // Active child A is onstage
    expect(offstagesInitial[0].offstage, isFalse);
    // Inactive child B is offstaged
    expect(offstagesInitial[1].offstage, isTrue);

    // Switch to index 1
    await tester.pumpWidget(
      wrap(
        const QueryaSwitchingBody(
          index: 1,
          children: [
            Text('A', key: Key('child-a')),
            Text('B', key: Key('child-b')),
          ],
        ),
      ),
    );

    // While animating, both are onstage
    await tester.pump(const Duration(milliseconds: 50));
    final offstagesAnimating =
        tester.widgetList<Offstage>(offstageFinder).toList();
    expect(offstagesAnimating[0].offstage, isFalse);
    expect(offstagesAnimating[1].offstage, isFalse);

    // Once settled, child A is offstaged, child B is onstage
    await tester.pumpAndSettle();
    final offstagesSettled =
        tester.widgetList<Offstage>(offstageFinder).toList();
    expect(offstagesSettled[0].offstage, isTrue);
    expect(offstagesSettled[1].offstage, isFalse);
  });

  testWidgets('preserves ScrollController offset across index switches',
      (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    Widget buildApp(int index) {
      return wrap(
        QueryaSwitchingBody(
          index: index,
          children: [
            ListView.builder(
              controller: scrollController,
              itemCount: 100,
              itemBuilder: (context, i) => SizedBox(
                height: 50,
                child: Text('Item $i'),
              ),
            ),
            const Center(child: Text('Other Pane')),
          ],
        ),
      );
    }

    await tester.pumpWidget(buildApp(0));
    await tester.pumpAndSettle();

    scrollController.jumpTo(250.0);
    await tester.pump();
    expect(scrollController.offset, 250.0);

    // Switch to index 1
    await tester.pumpWidget(buildApp(1));
    await tester.pumpAndSettle();
    expect(find.text('Other Pane'), findsOneWidget);

    // Switch back to index 0
    await tester.pumpWidget(buildApp(0));
    await tester.pumpAndSettle();

    expect(scrollController.offset, 250.0);
  });

  testWidgets(
      'preserves TextEditingController text and selection across index switches',
      (tester) async {
    final textController = TextEditingController(text: 'Initial Draft');
    addTearDown(textController.dispose);

    Widget buildApp(int index) {
      return wrap(
        QueryaSwitchingBody(
          index: index,
          children: [
            TextField(
              controller: textController,
            ),
            const Center(child: Text('Other Pane')),
          ],
        ),
      );
    }

    await tester.pumpWidget(buildApp(0));
    await tester.pumpAndSettle();

    textController.text = 'Modified query buffer';
    textController.selection = const TextSelection.collapsed(offset: 8);
    await tester.pump();

    // Switch to index 1
    await tester.pumpWidget(buildApp(1));
    await tester.pumpAndSettle();

    // Switch back to index 0
    await tester.pumpWidget(buildApp(0));
    await tester.pumpAndSettle();

    expect(textController.text, 'Modified query buffer');
    expect(textController.selection.baseOffset, 8);
  });
}

class _CounterPane extends StatefulWidget {
  const _CounterPane({super.key, required this.label});

  final String label;

  @override
  State<_CounterPane> createState() => _CounterPaneState();
}

class _CounterPaneState extends State<_CounterPane> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => setState(() => _count++),
        child: Text('${widget.label}:$_count'),
      ),
    );
  }
}
