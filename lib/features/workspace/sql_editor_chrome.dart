import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Outer chrome for SQL editors: border, surface, brand accent glow.
class SqlEditorChrome extends StatelessWidget {
  const SqlEditorChrome({super.key, required this.child});

  final Widget child;

  static const double outerRadius = 14;
  static const double innerRadius = 10;

  /// Accent glow strength; slightly softer on light themes.
  static double chromeGlowAlpha(Brightness brightness) =>
      brightness == Brightness.light ? 0.08 : 0.1;

  static double inlineGlowAlpha(Brightness brightness) =>
      brightness == Brightness.light ? 0.05 : 0.07;

  /// Toolbar strip above SQL editor (Postgres/MySQL workspaces).
  static material.BoxDecoration sqlToolbarDecoration(
    BuildContext context,
  ) {
    final workbench = context.workbench;
    return material.BoxDecoration(
      color: workbench.surface.withValues(alpha: 0.85),
      border: material.Border(
        bottom: material.BorderSide(
          color: workbench.borderSubtle.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  /// Decoration for compact SQL fields (dialogs) from theme tokens.
  static material.BoxDecoration inlineFieldDecoration(
    QueryaEditorTheme editor,
    QueryaWorkbenchTheme workbench, {
    Brightness brightness = Brightness.dark,
  }) {
    final border = editor.widgetBorder ?? workbench.borderSubtle;
    return material.BoxDecoration(
      color: editor.background,
      borderRadius: material.BorderRadius.circular(innerRadius),
      border: material.Border.all(
        color: border.withValues(alpha: 0.45),
      ),
      boxShadow: [
        material.BoxShadow(
          color: workbench.accent.withValues(
            alpha: inlineGlowAlpha(brightness),
          ),
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
      brightness: Theme.of(context).brightness,
    );
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.editorTheme;
    final workbench = context.workbench;
    final brightness = Theme.of(context).brightness;
    final border = editor.widgetBorder ?? workbench.borderSubtle;
    final glow = workbench.accent.withValues(
      alpha: chromeGlowAlpha(brightness),
    );

    return material.Container(
      decoration: material.BoxDecoration(
        borderRadius: material.BorderRadius.circular(outerRadius),
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
          borderRadius: material.BorderRadius.circular(outerRadius),
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
