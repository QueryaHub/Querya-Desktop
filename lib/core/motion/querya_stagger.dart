import 'package:flutter/material.dart';

import 'querya_motion.dart';
import 'querya_motion_context.dart';

/// Staggered fade-in for a fixed list — **first paint only**, capped at [maxStaggered].
///
/// Do not wrap virtualized / scrolling grids; use for history lists, recent
/// connections, etc.
class QueryaStagger extends StatefulWidget {
  const QueryaStagger({
    super.key,
    required this.children,
    this.maxStaggered = 8,
    this.step = const Duration(milliseconds: 30),
  });

  final List<Widget> children;
  final int maxStaggered;
  final Duration step;

  @override
  State<QueryaStagger> createState() => _QueryaStaggerState();
}

class _QueryaStaggerState extends State<QueryaStagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_played) return;
    _played = true;
    final n = widget.children.length.clamp(0, widget.maxStaggered);
    if (n == 0) return;

    final base = context.motionDuration(QueryaMotion.fast);
    if (base == QueryaMotion.instant) {
      _controller.value = 1;
      return;
    }

    final total = base + widget.step * n;
    _controller.duration = total;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.children.length;
    if (count == 0) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < count; i++)
              Opacity(
                opacity: _opacityFor(i, count),
                child: widget.children[i],
              ),
          ],
        );
      },
    );
  }

  double _opacityFor(int index, int count) {
    if (_controller.duration == null ||
        _controller.duration == Duration.zero) {
      return 1;
    }
    if (index >= widget.maxStaggered) return 1;

    final totalMs = _controller.duration!.inMilliseconds;
    if (totalMs <= 0) return 1;

    final stepMs = widget.step.inMilliseconds;
    final start = (stepMs * index) / totalMs;
    final end = (start + 0.35).clamp(0.0, 1.0);
    final t = _controller.value;
    if (t <= start) return 0;
    if (t >= end) return 1;
    return ((t - start) / (end - start)).clamp(0.0, 1.0);
  }
}
