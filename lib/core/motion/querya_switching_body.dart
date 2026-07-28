import 'package:flutter/material.dart';

import 'querya_motion.dart';
import 'querya_motion_context.dart';

/// Keep-alive indexed stack with opacity (+ optional slide) transitions.
///
/// Off-screen children stay mounted (SQL editor state, etc.). Prefer this over
/// hard `if` swaps for empty↔workspace and similar shell morphs.
///
/// Uses duration-token cubics ([QueryaMotion.standard] / enter / exit), not
/// [QueryaSpring] — springs stay for interruptible physics only.
class QueryaSwitchingBody extends StatelessWidget {
  const QueryaSwitchingBody({
    super.key,
    required this.index,
    required this.children,
    this.slide = const Offset(0.015, 0),
  });

  final int index;
  final List<Widget> children;

  /// Incoming slide (fraction of size). Zero disables slide.
  final Offset slide;

  @override
  Widget build(BuildContext context) {
    assert(children.isNotEmpty, 'QueryaSwitchingBody requires children');
    final safeIndex = index.clamp(0, children.length - 1);
    final duration = context.motionDuration(QueryaMotion.standard);
    final inCurve = context.motionCurve(QueryaMotion.enter);
    final outCurve = context.motionCurve(QueryaMotion.exit);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          Positioned.fill(
            child: _SwitchingLayer(
              active: i == safeIndex,
              duration: duration,
              inCurve: inCurve,
              outCurve: outCurve,
              slide: slide,
              child: children[i],
            ),
          ),
      ],
    );
  }
}

class _SwitchingLayer extends StatelessWidget {
  const _SwitchingLayer({
    required this.active,
    required this.duration,
    required this.inCurve,
    required this.outCurve,
    required this.slide,
    required this.child,
  });

  final bool active;
  final Duration duration;
  final Curve inCurve;
  final Curve outCurve;
  final Offset slide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curve = active ? inCurve : outCurve;
    // Isolate paint; pause child tickers when inactive (opacity anim still runs).
    final content = TickerMode(
      enabled: active,
      child: RepaintBoundary(child: child),
    );
    Widget layer = AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: duration,
      curve: curve,
      child: content,
    );

    if (slide != Offset.zero) {
      layer = AnimatedSlide(
        offset: active ? Offset.zero : slide,
        duration: duration,
        curve: curve,
        child: layer,
      );
    }

    return IgnorePointer(
      ignoring: !active,
      child: ExcludeFocus(
        excluding: !active,
        child: ExcludeSemantics(
          excluding: !active,
          child: layer,
        ),
      ),
    );
  }
}
