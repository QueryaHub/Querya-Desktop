import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Outer chrome for SQL editors: border, surface, brand accent glow.
class SqlEditorChrome extends StatelessWidget {
  const SqlEditorChrome({super.key, required this.child});

  final Widget child;

  static const double _outerRadius = 14;
  static const double _innerRadius = 10;

  /// Decoration for compact SQL fields (dialogs) from theme tokens.
  static material.BoxDecoration inlineFieldDecoration(
    QueryaEditorTheme editor,
    QueryaWorkbenchTheme workbench,
  ) {
    final border = editor.widgetBorder ?? workbench.borderSubtle;
    return material.BoxDecoration(
      color: editor.background,
      borderRadius: material.BorderRadius.circular(_innerRadius),
      border: material.Border.all(
        color: border.withValues(alpha: 0.45),
      ),
      boxShadow: [
        material.BoxShadow(
          color: workbench.accent.withValues(alpha: 0.07),
          blurRadius: 18,
          offset: const material.Offset(0, 6),
        ),
      ],
    );
  }

  static material.BoxDecoration inlineFieldDecorationFromContext(
    BuildContext context,
  ) {
    return inlineFieldDecoration(
      context.editorTheme,
      context.workbench,
    );
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.editorTheme;
    final workbench = context.workbench;
    final border = editor.widgetBorder ?? workbench.borderSubtle;
    final glow = workbench.accent.withValues(alpha: 0.1);

    return material.Container(
      decoration: material.BoxDecoration(
        borderRadius: material.BorderRadius.circular(_outerRadius),
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
          color: editor.background,
          borderRadius: material.BorderRadius.circular(_outerRadius),
          border: material.Border.all(
            color: border.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: material.Clip.antiAlias,
        child: child,
      ),
    );
  }
}
