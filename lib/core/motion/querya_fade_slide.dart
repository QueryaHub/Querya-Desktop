import 'package:flutter/material.dart';

import 'querya_motion.dart';
import 'querya_motion_context.dart';
import 'querya_spring.dart';

/// Fades and optionally slides [child] when the keyed child changes.
///
/// Uses a short spring-like curve when [QueryaSpring.springsEnabled], otherwise
/// duration tokens. Prefer wrapping content with a stable [Key] on [child].
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
    final useSpring = QueryaSpring.springsEnabled(context);
    final duration = context.motionDuration(
      useSpring ? QueryaMotion.standard : QueryaMotion.fast,
    );
    final curve = context.motionCurve(
      useSpring ? QueryaMotion.emphasized : QueryaMotion.enter,
    );

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
