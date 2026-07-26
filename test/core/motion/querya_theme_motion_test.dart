import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/motion/querya_theme_motion.dart';

void main() {
  group('QueryaThemeMotion.duration', () {
    test('instant when preference disabled', () {
      expect(
        QueryaThemeMotion.duration(
          preferenceEnabled: false,
          level: QueryaMotionLevel.full,
        ),
        QueryaMotion.instant,
      );
    });

    test('instant when motion off', () {
      expect(
        QueryaThemeMotion.duration(
          preferenceEnabled: true,
          level: QueryaMotionLevel.off,
        ),
        QueryaMotion.instant,
      );
    });

    test('instant when OS disables animations', () {
      expect(
        QueryaThemeMotion.duration(
          preferenceEnabled: true,
          level: QueryaMotionLevel.full,
          disableAnimations: true,
        ),
        QueryaMotion.instant,
      );
    });

    test('slow for full motion', () {
      expect(
        QueryaThemeMotion.duration(
          preferenceEnabled: true,
          level: QueryaMotionLevel.full,
        ),
        QueryaMotion.slow,
      );
    });

    test('halved slow for reduced motion', () {
      expect(
        QueryaThemeMotion.duration(
          preferenceEnabled: true,
          level: QueryaMotionLevel.reduced,
        ),
        Duration(microseconds: QueryaMotion.slow.inMicroseconds ~/ 2),
      );
    });
  });

  group('QueryaThemeMotion.curve', () {
    test('linear when not animating', () {
      expect(
        QueryaThemeMotion.curve(
          preferenceEnabled: false,
          level: QueryaMotionLevel.full,
        ),
        Curves.linear,
      );
    });

    test('emphasized when animating', () {
      expect(
        QueryaThemeMotion.curve(
          preferenceEnabled: true,
          level: QueryaMotionLevel.full,
        ),
        QueryaMotion.emphasized,
      );
    });
  });

  group('QueryaThemeMotion.enabled', () {
    test('true only when duration is non-zero', () {
      expect(
        QueryaThemeMotion.enabled(
          preferenceEnabled: true,
          level: QueryaMotionLevel.full,
        ),
        isTrue,
      );
      expect(
        QueryaThemeMotion.enabled(
          preferenceEnabled: true,
          level: QueryaMotionLevel.off,
        ),
        isFalse,
      );
    });
  });
}
