import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/motion/querya_spring.dart';
import 'package:querya_desktop/core/motion/querya_spring_controller.dart';

void main() {
  group('QueryaSpring presets', () {
    test('snappy is approximately critically damped', () {
      const s = QueryaSpring.snappy;
      final critical = 2 * math.sqrt(s.mass * s.stiffness);
      expect(s.damping, closeTo(critical, 0.01));
    });

    test('gentle is approximately critically damped', () {
      const s = QueryaSpring.gentle;
      final critical = 2 * math.sqrt(s.mass * s.stiffness);
      expect(s.damping, closeTo(critical, 0.05));
    });

    test('bouncy is underdamped relative to critical', () {
      const s = QueryaSpring.bouncy;
      final critical = 2 * math.sqrt(s.mass * s.stiffness);
      expect(s.damping, lessThan(critical));
    });

    test('simulation moves toward end', () {
      final sim = QueryaSpring.simulation(
        description: QueryaSpring.snappy,
        start: 0,
        end: 1,
        velocity: 0,
      );
      expect(sim.x(0), closeTo(0, 0.001));
      expect(sim.x(1), closeTo(1, 0.05));
      expect(sim.isDone(2), isTrue);
    });

    test('simulation with positive velocity leaves start quickly', () {
      final sim = QueryaSpring.simulation(
        description: QueryaSpring.bouncy,
        start: 0,
        end: 1,
        velocity: 5,
      );
      expect(sim.x(0.05), greaterThan(0));
    });
  });

  group('QueryaSpring.springsEnabled', () {
    testWidgets('true when motion is full', (tester) async {
      late bool enabled;
      await tester.pumpWidget(
        MaterialApp(
          home: QueryaMotionScope(
            level: QueryaMotionLevel.full,
            child: Builder(
              builder: (context) {
                enabled = QueryaSpring.springsEnabled(context);
                expect(context.motionSpringsEnabled, enabled);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(enabled, isTrue);
    });

    testWidgets('true when scope is absent (defaults to full)', (tester) async {
      late bool enabled;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              enabled = QueryaSpring.springsEnabled(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(enabled, isTrue);
    });

    testWidgets('false when motion is reduced', (tester) async {
      late bool enabled;
      await tester.pumpWidget(
        MaterialApp(
          home: QueryaMotionScope(
            level: QueryaMotionLevel.reduced,
            child: Builder(
              builder: (context) {
                enabled = QueryaSpring.springsEnabled(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(enabled, isFalse);
    });

    testWidgets('false when motion is off', (tester) async {
      late bool enabled;
      await tester.pumpWidget(
        MaterialApp(
          home: QueryaMotionScope(
            level: QueryaMotionLevel.off,
            child: Builder(
              builder: (context) {
                enabled = QueryaSpring.springsEnabled(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(enabled, isFalse);
    });

    testWidgets('false when OS disables animations', (tester) async {
      late bool enabled;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: QueryaMotionScope(
              level: QueryaMotionLevel.full,
              child: Builder(
                builder: (context) {
                  enabled = QueryaSpring.springsEnabled(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(enabled, isFalse);
    });
  });

  group('QueryaSpringController', () {
    testWidgets('retarget preserves continuity (no jump to end)', (tester) async {
      late QueryaSpringController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: _SpringHost(onCreated: (c) => controller = c),
        ),
      );

      controller.animateTo(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final mid = controller.value;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));

      controller.animateTo(0);
      await tester.pump();
      final afterRedirect = controller.value;
      expect(afterRedirect, closeTo(mid, 0.15));

      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(controller.value, closeTo(0, 0.01));
      expect(controller.isAnimating, isFalse);
      expect(controller.velocity, 0);
    });

    testWidgets('multiple redirects settle on final target', (tester) async {
      late QueryaSpringController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: _SpringHost(onCreated: (c) => controller = c),
        ),
      );

      controller.animateTo(1);
      await tester.pump(const Duration(milliseconds: 20));
      controller.animateTo(0.2);
      await tester.pump(const Duration(milliseconds: 20));
      controller.animateTo(1);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(controller.value, closeTo(1, 0.02));
      expect(controller.target, 1);
    });

    testWidgets('jumpTo cancels animation', (tester) async {
      late QueryaSpringController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: _SpringHost(onCreated: (c) => controller = c),
        ),
      );

      controller.animateTo(1);
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.isAnimating, isTrue);
      controller.jumpTo(0.5);
      expect(controller.value, 0.5);
      expect(controller.isAnimating, isFalse);
      expect(controller.velocity, 0);
    });

    testWidgets('animateTo same value with zero velocity settles immediately',
        (tester) async {
      late QueryaSpringController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: _SpringHost(onCreated: (c) => controller = c),
        ),
      );
      controller.jumpTo(0.3);
      controller.animateTo(0.3);
      expect(controller.value, 0.3);
      expect(controller.isAnimating, isFalse);
    });

    testWidgets('explicit velocity handoff is accepted', (tester) async {
      late QueryaSpringController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: _SpringHost(onCreated: (c) => controller = c),
        ),
      );
      controller.jumpTo(0);
      controller.animateTo(1, velocity: 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.value, greaterThan(0));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(controller.value, closeTo(1, 0.02));
    });

    testWidgets('snaps when springs disabled', (tester) async {
      late QueryaSpringController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: _SpringHost(
            useSprings: false,
            onCreated: (c) => controller = c,
          ),
        ),
      );

      controller.animateTo(1);
      expect(controller.value, 1);
      expect(controller.isAnimating, isFalse);
    });

    testWidgets('notifies listeners on animate', (tester) async {
      late QueryaSpringController controller;
      var notifications = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: _SpringHost(
            onCreated: (c) {
              controller = c;
              controller.addListener(() => notifications++);
            },
          ),
        ),
      );

      controller.animateTo(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(notifications, greaterThan(0));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('custom spring description is used', (tester) async {
      late QueryaSpringController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: _SpringHost(
            spring: QueryaSpring.gentle,
            onCreated: (c) => controller = c,
          ),
        ),
      );
      expect(identical(controller.spring, QueryaSpring.gentle), isTrue);
      controller.animateTo(1);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(controller.value, closeTo(1, 0.02));
    });
  });
}

class _SpringHost extends StatefulWidget {
  const _SpringHost({
    required this.onCreated,
    this.useSprings = true,
    this.spring = QueryaSpring.snappy,
  });

  final ValueChanged<QueryaSpringController> onCreated;
  final bool useSprings;
  final SpringDescription spring;

  @override
  State<_SpringHost> createState() => _SpringHostState();
}

class _SpringHostState extends State<_SpringHost>
    with SingleTickerProviderStateMixin {
  late final QueryaSpringController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QueryaSpringController(
      vsync: this,
      useSprings: widget.useSprings,
      spring: widget.spring,
    );
    widget.onCreated(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
