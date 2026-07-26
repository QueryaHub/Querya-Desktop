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
    expect(find.byKey(const Key('b')), findsOneWidget);

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

  testWidgets('reduced motion disables springs path (fast halved)',
      (tester) async {
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
        QueryaMotion.fast,
      ),
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
