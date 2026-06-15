import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';

void main() {
  group('QueryaMotion tokens', () {
    test('duration constants match design doc', () {
      expect(QueryaMotion.instant, Duration.zero);
      expect(QueryaMotion.fast, const Duration(milliseconds: 120));
      expect(QueryaMotion.standard, const Duration(milliseconds: 200));
      expect(QueryaMotion.slow, const Duration(milliseconds: 320));
    });

    test('curve constants are set', () {
      expect(QueryaMotion.enter, Curves.easeOutCubic);
      expect(QueryaMotion.exit, Curves.easeInCubic);
      expect(QueryaMotion.standardCurve, Curves.easeInOutCubic);
      expect(QueryaMotion.emphasized, Curves.easeInOutCubicEmphasized);
    });
  });

  group('effectiveDuration', () {
    testWidgets('returns token when motion is full', (tester) async {
      late Duration result;

      await tester.pumpWidget(
        _MotionProbe(
          disableAnimations: false,
          level: QueryaMotionLevel.full,
          onDuration: (d) => result = d,
        ),
      );

      expect(result, QueryaMotion.standard);
    });

    testWidgets('returns instant when OS disableAnimations is true', (
      tester,
    ) async {
      late Duration result;

      await tester.pumpWidget(
        _MotionProbe(
          disableAnimations: true,
          level: QueryaMotionLevel.full,
          onDuration: (d) => result = d,
        ),
      );

      expect(result, QueryaMotion.instant);
    });

    testWidgets('returns instant when motion level is off', (tester) async {
      late Duration result;

      await tester.pumpWidget(
        _MotionProbe(
          disableAnimations: false,
          level: QueryaMotionLevel.off,
          onDuration: (d) => result = d,
        ),
      );

      expect(result, QueryaMotion.instant);
    });

    testWidgets('halves duration when motion level is reduced', (tester) async {
      late Duration result;

      await tester.pumpWidget(
        _MotionProbe(
          disableAnimations: false,
          level: QueryaMotionLevel.reduced,
          onDuration: (d) => result = d,
        ),
      );

      expect(result, const Duration(milliseconds: 100));
    });

    testWidgets('defaults to full when QueryaMotionScope is absent', (
      tester,
    ) async {
      late Duration result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = context.motionDuration(QueryaMotion.fast);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(result, QueryaMotion.fast);
    });
  });

  group('effectiveCurve', () {
    testWidgets('returns linear when animations disabled', (tester) async {
      late Curve result;

      await tester.pumpWidget(
        _MotionCurveProbe(
          disableAnimations: true,
          level: QueryaMotionLevel.full,
          onCurve: (c) => result = c,
        ),
      );

      expect(result, Curves.linear);
    });

    testWidgets('returns token curve when motion is full', (tester) async {
      late Curve result;

      await tester.pumpWidget(
        _MotionCurveProbe(
          disableAnimations: false,
          level: QueryaMotionLevel.full,
          onCurve: (c) => result = c,
        ),
      );

      expect(result, QueryaMotion.enter);
    });
  });
}

class _MotionProbe extends StatelessWidget {
  const _MotionProbe({
    required this.disableAnimations,
    required this.level,
    required this.onDuration,
  });

  final bool disableAnimations;
  final QueryaMotionLevel level;
  final ValueChanged<Duration> onDuration;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: QueryaMotionScope(
          level: level,
          child: Builder(
            builder: (context) {
              onDuration(
                QueryaMotion.effectiveDuration(context, QueryaMotion.standard),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}

class _MotionCurveProbe extends StatelessWidget {
  const _MotionCurveProbe({
    required this.disableAnimations,
    required this.level,
    required this.onCurve,
  });

  final bool disableAnimations;
  final QueryaMotionLevel level;
  final ValueChanged<Curve> onCurve;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: QueryaMotionScope(
          level: level,
          child: Builder(
            builder: (context) {
              onCurve(QueryaMotion.effectiveCurve(context, QueryaMotion.enter));
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
