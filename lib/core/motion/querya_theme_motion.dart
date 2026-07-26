import 'package:flutter/animation.dart';

import 'querya_motion.dart';
import 'querya_motion_scope.dart';

/// Theme cross-fade timing gated by the Preferences toggle and motion level.
abstract final class QueryaThemeMotion {
  /// Effective theme transition duration.
  ///
  /// Returns [QueryaMotion.instant] when the preference is off, motion is
  /// [QueryaMotionLevel.off], or OS `disableAnimations` is set. Reduced halves
  /// [QueryaMotion.slow]; Full uses [QueryaMotion.slow].
  static Duration duration({
    required bool preferenceEnabled,
    required QueryaMotionLevel level,
    bool disableAnimations = false,
  }) {
    if (!preferenceEnabled ||
        disableAnimations ||
        level == QueryaMotionLevel.off) {
      return QueryaMotion.instant;
    }
    const token = QueryaMotion.slow;
    if (level == QueryaMotionLevel.reduced) {
      return Duration(microseconds: token.inMicroseconds ~/ 2);
    }
    return token;
  }

  /// Curve for theme transitions (emphasized when animating).
  static Curve curve({
    required bool preferenceEnabled,
    required QueryaMotionLevel level,
    bool disableAnimations = false,
  }) {
    if (duration(
          preferenceEnabled: preferenceEnabled,
          level: level,
          disableAnimations: disableAnimations,
        ) ==
        QueryaMotion.instant) {
      return Curves.linear;
    }
    return QueryaMotion.emphasized;
  }

  /// Whether [ShadcnAnimatedTheme] / [AnimatedQueryaTheme] should animate.
  static bool enabled({
    required bool preferenceEnabled,
    required QueryaMotionLevel level,
    bool disableAnimations = false,
  }) {
    return duration(
          preferenceEnabled: preferenceEnabled,
          level: level,
          disableAnimations: disableAnimations,
        ) !=
        QueryaMotion.instant;
  }
}
