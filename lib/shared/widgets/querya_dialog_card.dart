import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Dialog shell card: [Material] ink host + popover fill (avoids ListTile asserts
/// under opaque [DecoratedBox] on Flutter 3.44+).
class QueryaDialogCard extends material.StatelessWidget {
  const QueryaDialogCard({
    super.key,
    required this.child,
    this.constraints,
    this.borderColor,
  });

  final material.Widget child;
  final material.BoxConstraints? constraints;
  final material.Color? borderColor;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
    return material.Material(
      color: theme.popover,
      elevation: 0,
      shape: material.RoundedRectangleBorder(
        borderRadius: material.BorderRadius.circular(radius),
        side: material.BorderSide(color: borderColor ?? theme.border),
      ),
      clipBehavior: material.Clip.antiAlias,
      child: constraints == null
          ? child
          : material.ConstrainedBox(
              constraints: constraints!,
              child: child,
            ),
    );
  }
}
