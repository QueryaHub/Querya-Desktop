import 'package:flutter/material.dart';

import 'querya_motion.dart';
import 'querya_motion_context.dart';

/// Unified hover background / border using motion tokens (Responsive chrome).
///
/// **Scope:** selection / picker cards (e.g. connection type tiles). Dense
/// trees and explorer rows keep lighter `InkWell` / `MouseRegion` hover —
/// do not broaden adoption without an explicit follow-up.
class QueryaHoverSurface extends StatefulWidget {
  const QueryaHoverSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.border,
    this.padding,
    this.hoveredColor,
    this.idleColor = Colors.transparent,
    this.onTap,
    this.mouseCursor,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final EdgeInsetsGeometry? padding;
  final Color? hoveredColor;
  final Color idleColor;
  final VoidCallback? onTap;
  final MouseCursor? mouseCursor;

  @override
  State<QueryaHoverSurface> createState() => _QueryaHoverSurfaceState();
}

class _QueryaHoverSurfaceState extends State<QueryaHoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hovered = widget.hoveredColor ??
        scheme.onSurface.withValues(alpha: 0.06);
    final duration = context.motionDuration(QueryaMotion.fast);
    final curve = context.motionCurve(QueryaMotion.enter);

    Widget content = AnimatedContainer(
      duration: duration,
      curve: curve,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _hovered ? hovered : widget.idleColor,
        borderRadius: widget.borderRadius,
        border: widget.border,
      ),
      child: widget.child,
    );

    if (widget.onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: content,
      );
    }

    return MouseRegion(
      cursor: widget.mouseCursor ??
          (widget.onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic),
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: content,
    );
  }
}
