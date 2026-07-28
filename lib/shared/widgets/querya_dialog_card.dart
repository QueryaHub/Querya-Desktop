import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Dialog shell: [Material] popover fill (ListTile ink host) under the same
/// [Container] constraints as the pre-migration shell.
///
/// Re-applies the ambient [DefaultTextStyle] / [IconTheme] after [Material],
/// which would otherwise inject [ThemeData.textTheme] and bloat dense dialog
/// chrome (Extension Manager overflow).
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
    final borderRadius = material.BorderRadius.circular(radius);
    final textStyle = material.DefaultTextStyle.of(context).style;
    final iconTheme = material.IconTheme.of(context);

    final card = material.Material(
      color: theme.popover,
      elevation: 0,
      shape: material.RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: material.BorderSide(color: borderColor ?? theme.border),
      ),
      clipBehavior: material.Clip.antiAlias,
      child: material.DefaultTextStyle(
        style: textStyle,
        child: material.IconTheme(
          data: iconTheme,
          child: child,
        ),
      ),
    );

    if (constraints == null) return card;

    return material.Container(
      constraints: constraints,
      child: card,
    );
  }
}
