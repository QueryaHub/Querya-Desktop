import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/motion/querya_stagger.dart';

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

  List<Widget> texts(int n) => [
        for (var i = 0; i < n; i++) Text('item-$i', key: ValueKey('item-$i')),
      ];

  double opacityOf(WidgetTester tester, String text) {
    final opacityWidget = tester.widget<Opacity>(
      find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first,
    );
    return opacityWidget.opacity;
  }

  testWidgets('empty children render SizedBox.shrink', (tester) async {
    await tester.pumpWidget(wrap(const QueryaStagger(children: [])));
    expect(find.byType(QueryaStagger), findsOneWidget);
    expect(find.byType(Column), findsNothing);
    expect(find.textContaining('item-'), findsNothing);
  });

  testWidgets('first paint staggers then reaches full opacity', (tester) async {
    await tester.pumpWidget(wrap(QueryaStagger(children: texts(4))));

    await tester.pump(const Duration(milliseconds: 40));
    final early = opacityOf(tester, 'item-0');
    final late = opacityOf(tester, 'item-3');
    expect(early, greaterThanOrEqualTo(late));

    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      expect(opacityOf(tester, 'item-$i'), 1.0);
    }
  });

  testWidgets('items beyond maxStaggered start fully opaque', (tester) async {
    await tester.pumpWidget(
      wrap(
        QueryaStagger(
          maxStaggered: 2,
          children: texts(4),
        ),
      ),
    );
    await tester.pump();
    expect(opacityOf(tester, 'item-2'), 1.0);
    expect(opacityOf(tester, 'item-3'), 1.0);
  });

  testWidgets('motion off skips stagger (all opaque immediately)',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        QueryaStagger(children: texts(3)),
        level: QueryaMotionLevel.off,
      ),
    );
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      expect(opacityOf(tester, 'item-$i'), 1.0);
    }
  });

  testWidgets('plays only once across rebuilds', (tester) async {
    await tester.pumpWidget(wrap(QueryaStagger(children: texts(2))));
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(QueryaStagger(children: texts(2))));
    await tester.pump();
    expect(opacityOf(tester, 'item-0'), 1.0);
    expect(opacityOf(tester, 'item-1'), 1.0);
  });

  testWidgets('custom step affects stagger order timing', (tester) async {
    await tester.pumpWidget(
      wrap(
        QueryaStagger(
          step: const Duration(milliseconds: 80),
          children: texts(3),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));
    expect(opacityOf(tester, 'item-0'), greaterThan(0));
    expect(opacityOf(tester, 'item-2'), 0);
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'item-2'), 1.0);
  });

  testWidgets('OS disableAnimations skips stagger', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: QueryaMotionScope(
            level: QueryaMotionLevel.full,
            child: Scaffold(
              body: QueryaStagger(children: texts(3)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      expect(opacityOf(tester, 'item-$i'), 1.0);
    }
  });
}
