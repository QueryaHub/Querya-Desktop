import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_colors.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Outer chrome for SQL editors: subtle border, surface fill, soft cyan glow.
class SqlEditorChrome extends StatelessWidget {
  const SqlEditorChrome({super.key, required this.child});

  final Widget child;

  static material.BoxDecoration inlineFieldDecoration(ThemeData theme) {
    final cs = theme.colorScheme;
    return material.BoxDecoration(
      color: cs.card,
      borderRadius: material.BorderRadius.circular(10),
      border: material.Border.all(
        color: cs.border.withValues(alpha: 0.45),
      ),
      boxShadow: [
        material.BoxShadow(
          color: QueryaColors.accentCyan.withValues(alpha: 0.07),
          blurRadius: 18,
          offset: const material.Offset(0, 6),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final glow = QueryaColors.accentCyan.withValues(alpha: 0.1);
    return material.Container(
      decoration: material.BoxDecoration(
        borderRadius: material.BorderRadius.circular(14),
        boxShadow: [
          material.BoxShadow(
            color: glow,
            blurRadius: 28,
            spreadRadius: 0,
            offset: const material.Offset(0, 10),
          ),
        ],
      ),
      child: material.Container(
        decoration: material.BoxDecoration(
          color: cs.card,
          borderRadius: material.BorderRadius.circular(14),
          border: material.Border.all(
            color: cs.border.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: material.Clip.antiAlias,
        child: child,
      ),
    );
  }
}
