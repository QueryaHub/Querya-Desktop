import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';

/// Outer chrome for SQL editors and the results under them: one rounded card
/// with a border.
class SqlEditorChrome extends StatefulWidget {
  const SqlEditorChrome({
    super.key,
    required this.child,
    this.background,
    this.showFocus = true,
  });

  final Widget child;

  /// The card's surface; the editor background by default.
  final material.Color? background;

  /// Whether the border takes the accent while something inside has the
  /// keyboard. Off for a card with nothing to type in (the results).
  final bool showFocus;

  static const double outerRadius = 14;
  static const double innerRadius = 10;

  static double inlineGlowAlpha(Brightness brightness) =>
      brightness == Brightness.light ? 0.05 : 0.07;

  /// Toolbar strip above SQL editor (Postgres/MySQL workspaces).
  static material.BoxDecoration sqlToolbarDecoration(
    BuildContext context,
  ) {
    final workbench = context.workbench;
    return material.BoxDecoration(
      color: workbench.surface,
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
      brightness: context.colors.brightness,
    );
  }

  @override
  State<SqlEditorChrome> createState() => _SqlEditorChromeState();
}

class _SqlEditorChromeState extends State<SqlEditorChrome> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final editor = context.editorTheme;
    final workbench = context.workbench;
    final border = editor.widgetBorder ?? workbench.borderSubtle;
    final surface = widget.background ?? editor.background;

    // One framed card, the same for the editor and the results. No glow: the
    // only accent is the border while the editor has the keyboard (#1558).
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) {
        if (widget.showFocus) setState(() => _focused = v);
      },
      child: material.Container(
        decoration: material.BoxDecoration(
          color: surface,
          borderRadius: material.BorderRadius.circular(SqlEditorChrome.outerRadius),
          border: material.Border.all(
            color: widget.showFocus && _focused
                ? workbench.accent.withValues(alpha: 0.6)
                : border.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: material.Clip.antiAlias,
        child: widget.child,
      ),
    );
  }
}
