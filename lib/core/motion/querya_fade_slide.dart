import 'package:flutter/material.dart';

import 'querya_motion.dart';
import 'querya_motion_context.dart';

/// Fades and optionally slides [child] when the keyed child changes.
///
/// Uses duration-token cubic curves ([QueryaMotion.standard] / [QueryaMotion.enter]),
/// not [QueryaSpring] — reserve springs for interruptible physics (tab indicator,
/// drag settle). Prefer wrapping content with a stable [Key] on [child].
class QueryaFadeSlide extends StatelessWidget {
  const QueryaFadeSlide({
    super.key,
    required this.child,
    this.offset = const Offset(0, 0.02),
    this.alignment = Alignment.center,
  });

  final Widget child;

  /// Fractional slide for the incoming child (of parent size).
  final Offset offset;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final duration = context.motionDuration(QueryaMotion.standard);
    final curve = context.motionCurve(QueryaMotion.enter);

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: curve,
      switchOutCurve: context.motionCurve(QueryaMotion.exit),
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(begin: offset, end: Offset.zero)
            .animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
