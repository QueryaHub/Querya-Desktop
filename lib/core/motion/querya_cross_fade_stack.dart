import 'package:flutter/material.dart';

import 'querya_motion.dart';
import 'querya_motion_context.dart';

/// Like [IndexedStack] but cross-fades the active child; off-screen children
/// stay mounted (preserves SQL editor state, etc.).
///
/// Enter/exit curves and index clamping match [QueryaSwitchingBody] (without
/// the optional slide).
class QueryaCrossFadeStack extends StatelessWidget {
  const QueryaCrossFadeStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    assert(children.isNotEmpty, 'QueryaCrossFadeStack requires children');
    final safeIndex = index.clamp(0, children.length - 1);
    final duration = context.motionDuration(QueryaMotion.standard);
    final inCurve = context.motionCurve(QueryaMotion.enter);
    final outCurve = context.motionCurve(QueryaMotion.exit);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: i != safeIndex,
              child: ExcludeFocus(
                excluding: i != safeIndex,
                child: ExcludeSemantics(
                  excluding: i != safeIndex,
                  child: AnimatedOpacity(
                    opacity: i == safeIndex ? 1 : 0,
                    duration: duration,
                    curve: i == safeIndex ? inCurve : outCurve,
                    child: TickerMode(
                      enabled: i == safeIndex,
                      child: RepaintBoundary(child: children[i]),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
