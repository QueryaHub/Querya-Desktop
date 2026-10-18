import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';

/// A raised surface: the card colour, a hairline border, rounded corners
/// (#1734, epic #1465). Replaces shadcn's `Card`.
class QueryaCard extends material.StatelessWidget {
  const QueryaCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 10,
  });

  final material.Widget child;

  /// Inside the border; none by default (the child pads itself).
  final material.EdgeInsetsGeometry? padding;
  final double radius;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = context.colors;
    return material.Container(
      padding: padding,
      decoration: material.BoxDecoration(
        color: cs.card,
        borderRadius: material.BorderRadius.circular(radius),
        border: material.Border.all(color: cs.border.withValues(alpha: 0.7)),
      ),
      child: child,
    );
  }
}
