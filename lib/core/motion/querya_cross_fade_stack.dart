import 'package:flutter/material.dart';

import 'querya_motion.dart';
import 'querya_motion_context.dart';

/// Like [IndexedStack] but cross-fades the active child; off-screen children
/// stay mounted (preserves SQL editor state, etc.).
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
    final duration = context.motionDuration(QueryaMotion.standard);
    final curve = context.motionCurve(QueryaMotion.enter);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: index != i,
              child: ExcludeFocus(
                excluding: index != i,
                child: ExcludeSemantics(
                  excluding: index != i,
                  child: AnimatedOpacity(
                    opacity: index == i ? 1 : 0,
                    duration: duration,
                    curve: curve,
                    child: TickerMode(
                      enabled: index == i,
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
