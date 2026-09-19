import 'package:flutter/material.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/ui/querya_tree_tokens.dart';

/// Vertical indent guides for the connections tree (UI-05).
///
/// Paints one 1px line per [depth] in the left gutter, then pads [child]
/// by `leading + depth * step`. No animation — cheap [CustomPaint] only.
class QueryaTreeIndentGuide extends StatelessWidget {
  const QueryaTreeIndentGuide({
    super.key,
    required this.depth,
    required this.child,
    this.step = QueryaTreeTokens.indent,
    this.leading = 0,
    this.padding = EdgeInsets.zero,
  });

  /// Number of guide lines (and indent bands).
  final int depth;

  final Widget child;

  /// Width of one indent band. Defaults to [QueryaTreeTokens.indent].
  final double step;

  /// Extra left inset before the first band (SDUI root / leaf alignment).
  final double leading;

  /// Additional padding (top/right/bottom, extra left).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final left = leading + depth * step;
    final inset = padding.add(EdgeInsets.only(left: left));
    final content = left == 0 && padding == EdgeInsets.zero
        ? child
        : Padding(padding: inset, child: child);

    if (depth <= 0) return content;

    final base = QueryaThemeScope.maybeOf(context)?.workbench.borderSubtle ??
        Theme.of(context).colorScheme.outline;
    final color = base.withValues(alpha: QueryaTreeTokens.guideAlpha);

    return CustomPaint(
      painter: _QueryaTreeIndentGuidePainter(
        depth: depth,
        step: step,
        leading: leading,
        color: color,
      ),
      child: content,
    );
  }
}

class _QueryaTreeIndentGuidePainter extends CustomPainter {
  _QueryaTreeIndentGuidePainter({
    required this.depth,
    required this.step,
    required this.leading,
    required this.color,
  });

  final int depth;
  final double step;
  final double leading;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = QueryaTreeTokens.guideWidth
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < depth; i++) {
      final x = leading + i * step + QueryaTreeTokens.guideInset;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _QueryaTreeIndentGuidePainter oldDelegate) {
    return depth != oldDelegate.depth ||
        step != oldDelegate.step ||
        leading != oldDelegate.leading ||
        color != oldDelegate.color;
  }
}
