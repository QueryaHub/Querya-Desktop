import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';

/// Standard empty state placeholder for lists, search results, tabs, and query outputs.
class QueryaEmptyState extends material.StatelessWidget {
  const QueryaEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.action,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  /// Main message or title.
  final String title;

  /// Optional secondary explanatory text.
  final String? description;

  /// Optional icon widget or icon data.
  final material.Widget? icon;

  /// Optional custom action widget (e.g. a button).
  final material.Widget? action;

  /// Optional text label for default action button.
  final String? actionLabel;

  /// Optional callback for default action button.
  final material.VoidCallback? onAction;

  /// When true, renders with tighter padding and smaller fonts (suitable for sidebars or popovers).
  final bool compact;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;

    final iconColor = (workbench?.mutedForeground ?? cs.mutedForeground).withValues(alpha: 0.6);
    final iconBgColor = cs.muted.withValues(alpha: 0.25);

    material.Widget? iconWidget = icon;
    if (iconWidget != null) {
      final iconDimension = compact ? 36.0 : 54.0;
      final iconSize = compact ? 18.0 : 28.0;

      iconWidget = material.Container(
        width: iconDimension,
        height: iconDimension,
        decoration: material.BoxDecoration(
          color: iconBgColor,
          shape: material.BoxShape.circle,
        ),
        child: material.Center(
          child: material.IconTheme(
            data: material.IconThemeData(
              size: iconSize,
              color: iconColor,
            ),
            child: iconWidget,
          ),
        ),
      );
    }

    material.Widget? actionWidget = action;
    if (actionWidget == null && actionLabel != null && onAction != null) {
      actionWidget = OutlineButton(
        size: compact ? ButtonSize.small : ButtonSize.normal,
        onPressed: onAction,
        child: Text(actionLabel!),
      );
    }

    return material.Center(
      child: material.Padding(
        padding: material.EdgeInsets.all(compact ? 16.0 : 32.0),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.center,
          children: [
            if (iconWidget != null) ...[
              iconWidget,
              Gap(compact ? 10 : 16),
            ],
            material.Text(
              title,
              textAlign: material.TextAlign.center,
              style: material.TextStyle(
                fontSize: compact ? 13 : 15,
                fontWeight: material.FontWeight.w600,
                color: cs.foreground,
              ),
            ),
            if (description != null && description!.isNotEmpty) ...[
              Gap(compact ? 4 : 6),
              material.ConstrainedBox(
                constraints: const material.BoxConstraints(maxWidth: 360),
                child: material.Text(
                  description!,
                  textAlign: material.TextAlign.center,
                  style: material.TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: workbench?.mutedForeground ?? cs.mutedForeground,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (actionWidget != null) ...[
              Gap(compact ? 12 : 20),
              actionWidget,
            ],
          ],
        ),
      ),
    );
  }
}
