import 'package:flutter/material.dart';

import 'querya_motion.dart';

extension QueryaMotionContext on BuildContext {
  /// Token duration after OS / in-app reduced-motion rules.
  Duration motionDuration(Duration token) =>
      QueryaMotion.effectiveDuration(this, token);

  /// Token curve after OS / in-app reduced-motion rules.
  Curve motionCurve(Curve token) => QueryaMotion.effectiveCurve(this, token);
}
