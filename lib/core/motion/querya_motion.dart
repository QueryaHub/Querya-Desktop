import 'package:flutter/material.dart';

import 'querya_motion_scope.dart';

/// Shared animation durations and curves for Querya Desktop.
///
/// Widgets should use [effectiveDuration] / [effectiveCurve] (or the
/// [BuildContext] helpers in [querya_motion_context.dart]) so OS and in-app
/// reduced-motion settings apply consistently.
abstract final class QueryaMotion {
  /// No animation — used when motion is disabled.
  static const Duration instant = Duration.zero;

  /// Hover, small state changes.
  static const Duration fast = Duration(milliseconds: 120);

  /// Dialogs, menus, general surface transitions.
  static const Duration standard = Duration(milliseconds: 200);

  /// Emphasized transitions (theme cross-fade, large surfaces).
  static const Duration slow = Duration(milliseconds: 320);

  /// Connection / SDUI tree expand: chevron rotation **and** height morph share
  /// this duration so one gesture does not finish on two clocks (#480).
  static const Duration treeExpand = standard;

  /// Elements appearing (decelerate).
  static const Curve enter = Curves.easeOutCubic;

  /// Elements leaving (accelerate).
  static const Curve exit = Curves.easeInCubic;

  /// Move or resize in place.
  static const Curve standardCurve = Curves.easeInOutCubic;

  /// Hero / theme transitions.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Curve for [treeExpand] (chevron + [QueryaAnimatedExpand] height).
  static const Curve treeExpandCurve = enter;

  /// Returns [token] adjusted for accessibility and [QueryaMotionScope] level.
  static Duration effectiveDuration(BuildContext context, Duration token) {
    if (token == instant) return instant;
    if (MediaQuery.disableAnimationsOf(context)) return instant;

    final level = QueryaMotionScope.maybeOf(context);
    switch (level) {
      case QueryaMotionLevel.off:
        return instant;
      case QueryaMotionLevel.reduced:
        final halved = Duration(
          microseconds: token.inMicroseconds ~/ 2,
        );
        return halved == instant ? fast : halved;
      case QueryaMotionLevel.full:
      case null:
        return token;
    }
  }

  /// Returns [token] unless motion is fully disabled (then [Curves.linear]).
  static Curve effectiveCurve(BuildContext context, Curve token) {
    if (MediaQuery.disableAnimationsOf(context)) return Curves.linear;
    if (QueryaMotionScope.maybeOf(context) == QueryaMotionLevel.off) {
      return Curves.linear;
    }
    return token;
  }
}
