import 'package:flutter/material.dart';

import 'querya_motion.dart';
import 'querya_motion_context.dart';

/// Animates height when [expanded] toggles (connection tree sections, etc.).
///
/// Height morph via [AnimatedSize] is **skipped** when:
/// - Motion is Off / OS `disableAnimations` (effective duration is zero), or
/// - [estimatedChildCount] exceeds [skipSizeAnimationAbove] (large lists —
///   same spirit as SDUI flat trees that avoid fighting `itemExtent`).
///
/// Chevron rotation at call sites stays independent and cheap.
class QueryaAnimatedExpand extends StatelessWidget {
  const QueryaAnimatedExpand({
    super.key,
    required this.expanded,
    required this.child,
    this.alignment = Alignment.topCenter,
    this.estimatedChildCount,
    this.skipSizeAnimationAbove = defaultSkipSizeAnimationAbove,
  });

  /// Matches [kConnectionTreeEagerThreshold]: above this, expand is instant.
  static const int defaultSkipSizeAnimationAbove = 24;

  final bool expanded;
  final Widget child;
  final Alignment alignment;

  /// When known, used to skip multi-frame [AnimatedSize] for large subtrees.
  final int? estimatedChildCount;

  /// Instant expand/collapse when [estimatedChildCount] is greater than this.
  final int skipSizeAnimationAbove;

  @override
  Widget build(BuildContext context) {
    final duration = context.motionDuration(QueryaMotion.treeExpand);
    final curve = context.motionCurve(QueryaMotion.treeExpandCurve);
    final large = estimatedChildCount != null &&
        estimatedChildCount! > skipSizeAnimationAbove;
    final skipMorph = duration == Duration.zero || large;

    final content = expanded
        ? child
        : const SizedBox(width: double.infinity, height: 0);

    if (skipMorph) {
      return content;
    }

    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      clipBehavior: Clip.hardEdge,
      child: content,
    );
  }
}
