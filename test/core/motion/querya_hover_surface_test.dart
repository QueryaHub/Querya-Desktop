import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_hover_surface.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';

void main() {
  Widget wrap(
    Widget child, {
    QueryaMotionLevel level = QueryaMotionLevel.full,
  }) {
    return MaterialApp(
      home: QueryaMotionScope(
        level: level,
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  Color? containerColor(WidgetTester tester) {
    final animated =
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final decoration = animated.decoration as BoxDecoration?;
    return decoration?.color;
  }

  testWidgets('starts with idle color', (tester) async {
    const idle = Color(0x00000000);
    await tester.pumpWidget(
      wrap(
        const QueryaHoverSurface(
          idleColor: idle,
          hoveredColor: Color(0xFF112233),
          child: SizedBox(width: 80, height: 40, child: Text('row')),
        ),
      ),
    );
    expect(containerColor(tester), idle);
  });

  testWidgets('applies hovered color on mouse enter and clears on exit',
      (tester) async {
    const idle = Color(0x00000000);
    const hovered = Color(0xFF112233);
    await tester.pumpWidget(
      wrap(
        const QueryaHoverSurface(
          idleColor: idle,
          hoveredColor: hovered,
          child: SizedBox(width: 80, height: 40, child: Text('row')),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.text('row')));
    await tester.pump();
    expect(containerColor(tester), hovered);

    await gesture.moveTo(const Offset(0, 0));
    await tester.pump();
    expect(containerColor(tester), idle);
  });

  testWidgets('onTap fires', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        QueryaHoverSurface(
          onTap: () => taps++,
          child: const SizedBox(width: 80, height: 40, child: Text('tap')),
        ),
      ),
    );
    await tester.tap(find.text('tap'));
    expect(taps, 1);
  });

  testWidgets('AnimatedContainer uses fast motion duration', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaHoverSurface(
          child: SizedBox(width: 40, height: 20),
        ),
      ),
    );
    final animated =
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect(animated.duration, QueryaMotion.fast);
    expect(animated.curve, QueryaMotion.enter);
  });

  testWidgets('respects motion off (instant hover transition)', (tester) async {
    await tester.pumpWidget(
      wrap(
        const QueryaHoverSurface(
          child: SizedBox(width: 40, height: 20, child: Text('h')),
        ),
        level: QueryaMotionLevel.off,
      ),
    );
    final animated =
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect(animated.duration, QueryaMotion.instant);
  });

  testWidgets('uses theme fallback hovered color when unset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: const ThemeData(
          colorScheme: ColorScheme.light(primary: Colors.teal),
        ),
        home: const QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: Scaffold(
            body: Center(
              child: QueryaHoverSurface(
                child: SizedBox(width: 40, height: 20, child: Text('theme')),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('theme')));
    await tester.pump();

    final color = containerColor(tester);
    expect(color, isNotNull);
    expect(color, isNot(Colors.transparent));
  });

  testWidgets('click cursor when onTap provided', (tester) async {
    await tester.pumpWidget(
      wrap(
        QueryaHoverSurface(
          onTap: () {},
          child: const SizedBox(width: 40, height: 20, child: Text('c')),
        ),
      ),
    );
    final region = tester.widget<MouseRegion>(
      find.descendant(
        of: find.byType(QueryaHoverSurface),
        matching: find.byType(MouseRegion),
      ),
    );
    expect(region.cursor, SystemMouseCursors.click);
  });
}
