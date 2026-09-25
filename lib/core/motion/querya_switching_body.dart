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

class _SwitchingLayer extends StatefulWidget {
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
  State<_SwitchingLayer> createState() => _SwitchingLayerState();
}

class _SwitchingLayerState extends State<_SwitchingLayer> {
  late bool _offstage;

  @override
  void initState() {
    super.initState();
    _offstage = !widget.active;
  }

  @override
  void didUpdateWidget(covariant _SwitchingLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) {
      _offstage = false;
    } else if (oldWidget.active && !widget.active) {
      if (widget.duration == Duration.zero) {
        _offstage = true;
      }
    }
  }

  void _handleOpacityEnd() {
    if (!mounted) return;
    if (!widget.active && !_offstage) {
      setState(() {
        _offstage = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final curve = widget.active ? widget.inCurve : widget.outCurve;
    // Isolate paint; pause child tickers when inactive (opacity anim still runs).
    // Inactive child is offstaged once the exit transition completes to avoid
    // redundant layout passes during desktop window resizing (#901).
    final content = TickerMode(
      enabled: widget.active,
      child: RepaintBoundary(
        child: Offstage(
          offstage: _offstage,
          child: widget.child,
        ),
      ),
    );
    Widget layer = AnimatedOpacity(
      opacity: widget.active ? 1 : 0,
      duration: widget.duration,
      curve: curve,
      onEnd: _handleOpacityEnd,
      child: content,
    );

    if (widget.slide != Offset.zero) {
      layer = AnimatedSlide(
        offset: widget.active ? Offset.zero : widget.slide,
        duration: widget.duration,
        curve: curve,
        child: layer,
      );
    }

    return IgnorePointer(
      ignoring: !widget.active,
      child: ExcludeFocus(
        excluding: !widget.active,
        child: ExcludeSemantics(
          excluding: !widget.active,
          child: layer,
        ),
      ),
    );
  }
}
