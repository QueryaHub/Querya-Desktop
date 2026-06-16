import 'package:flutter/material.dart';

import 'querya_motion.dart';
import 'querya_motion_context.dart';

/// Animates height when [expanded] toggles (connection tree sections, etc.).
class QueryaAnimatedExpand extends StatelessWidget {
  const QueryaAnimatedExpand({
    super.key,
    required this.expanded,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final bool expanded;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: context.motionDuration(QueryaMotion.standard),
      curve: context.motionCurve(QueryaMotion.enter),
      alignment: alignment,
      clipBehavior: Clip.hardEdge,
      child:
          expanded ? child : const SizedBox(width: double.infinity, height: 0),
    );
  }
}
