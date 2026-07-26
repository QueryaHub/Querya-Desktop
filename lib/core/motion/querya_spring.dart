import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'querya_motion_scope.dart';

/// Spring presets for Fluid UI (interruptible / redirectable motion).
///
/// Tuned toward critically damped motion (~Apple Response 0.3–0.5s feel).
/// Use with [SpringSimulation] / [AnimationController.animateWith], not fixed
/// [Duration] curves, when [springsEnabled] is true.
abstract final class QueryaSpring {
  /// Snappy panels / dialogs / tab indicator (~0.3s Response feel).
  static const SpringDescription snappy = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 40, // ≈ 2 * sqrt(stiffness * mass) — critically damped
  );

  /// Softer sheet / sidebar settle (~0.5s Response feel).
  static const SpringDescription gentle = SpringDescription(
    mass: 1,
    stiffness: 180,
    damping: 26.83,
  );

  /// Slight underdamped bounce for flicks / inertial settles.
  static const SpringDescription bouncy = SpringDescription(
    mass: 1,
    stiffness: 300,
    damping: 20,
  );

  /// Whether interactive surfaces should use springs (Full motion only).
  ///
  /// Reduced / Off / OS `disableAnimations` fall back to duration tokens or
  /// instant transitions.
  static bool springsEnabled(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return false;
    final level = QueryaMotionScope.maybeOf(context);
    return level == null || level == QueryaMotionLevel.full;
  }

  /// Builds a [SpringSimulation] from [start] toward [end].
  ///
  /// Pass [velocity] from the previous simulation / gesture for handoff
  /// (redirectable / interruptible).
  static SpringSimulation simulation({
    required SpringDescription description,
    required double start,
    required double end,
    double velocity = 0,
  }) {
    return SpringSimulation(description, start, end, velocity);
  }
}
