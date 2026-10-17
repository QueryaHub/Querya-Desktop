import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

import 'app_dialog.dart';
import 'querya_button.dart';
import 'querya_dialog_card.dart';

/// Standard modal dialog shell with title, optional description, icon, content, and actions.
class QueryaModalDialog extends material.StatelessWidget {
  const QueryaModalDialog({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.iconColor,
    this.iconBackgroundColor,
    this.content,
    this.actions,
    this.constraints = const material.BoxConstraints(maxWidth: 480),
    this.onClose,
    this.showCloseButton = false,
  });

  /// Dialog title (plain string or custom widget).
  final material.Widget title;

  /// Optional subtitle or explanatory description.
  final material.Widget? description;

  /// Optional header icon.
  final material.Widget? icon;

  /// Foreground color for the icon. Defaults to primary/accent color.
  final material.Color? iconColor;

  /// Background color for the icon badge. Defaults to iconColor with alpha.
  final material.Color? iconBackgroundColor;

  /// Main dialog body content.
  final material.Widget? content;

  /// Bottom action buttons (e.g. Cancel, Submit).
  final List<material.Widget>? actions;

  /// Card sizing constraints. Defaults to max width of 480px.
  final material.BoxConstraints constraints;

  /// Callback when close button is clicked.
  final material.VoidCallback? onClose;

  /// Whether to show the top-right close button.
  final bool showCloseButton;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = context.colors;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;

    material.Widget? leadingIcon = icon;
    if (leadingIcon != null) {
      final effectiveIconColor =
          iconColor ?? workbench?.accent ?? cs.primary;
      final effectiveBgColor = iconBackgroundColor ??
          effectiveIconColor.withValues(alpha: 0.14);

      leadingIcon = material.Container(
        padding: const material.EdgeInsets.all(8),
        decoration: material.BoxDecoration(
          color: effectiveBgColor,
          borderRadius: material.BorderRadius.circular(8),
        ),
        child: material.IconTheme(
          data: material.IconThemeData(
            color: effectiveIconColor,
            size: 22,
          ),
          child: leadingIcon,
        ),
      );
    }

    return QueryaDialogCard(
      constraints: constraints,
      child: material.Padding(
        padding: const material.EdgeInsets.all(20),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            // Header
            material.Row(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                if (leadingIcon != null) ...[
                  leadingIcon,
                  const material.SizedBox(width: 14),
                ],
                material.Expanded(
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    mainAxisSize: material.MainAxisSize.min,
                    children: [
                      material.DefaultTextStyle(
                        style: material.TextStyle(
                          fontSize: 16,
                          fontWeight: material.FontWeight.w600,
                          color: cs.foreground,
                        ),
                        child: title,
                      ),
                      if (description != null) ...[
                        const material.SizedBox(height: 4),
                        material.DefaultTextStyle(
                          style: material.TextStyle(
                            fontSize: 13,
                            color: workbench?.mutedForeground ?? cs.mutedForeground,
                          ),
                          child: description!,
                        ),
                      ],
                    ],
                  ),
                ),
                if (showCloseButton || onClose != null)
                  material.Padding(
                    padding: const material.EdgeInsets.only(left: 8),
                    child: QueryaButton.icon(
                      icon: material.Icons.close_rounded,
                      tooltip: 'Close',
                      size: QueryaControlSize.sm,
                      onPressed:
                          onClose ?? () => material.Navigator.of(context).pop(),
                    ),
                  ),
              ],
            ),

            // Content
            if (content != null) ...[
              const material.SizedBox(height: 16),
              constraints.hasBoundedHeight
                  ? material.Flexible(child: content!)
                  : content!,
            ],

            // Actions
            if (actions != null && actions!.isNotEmpty) ...[
              const material.SizedBox(height: 20),
              material.Align(
                alignment: material.Alignment.centerRight,
                // Buttons of the footer without an explicit size are `lg`.
                child: QueryaControlScope(
                  size: QueryaControlSize.lg,
                  child: material.Wrap(
                    alignment: material.WrapAlignment.end,
                    crossAxisAlignment: material.WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions!,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard confirmation dialog with Confirm and Cancel actions.
class QueryaConfirmDialog extends material.StatelessWidget {
  const QueryaConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.isDestructive = false,
    this.icon,
    this.onConfirm,
    this.onCancel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;
  final material.IconData? icon;
  final material.VoidCallback? onConfirm;
  final material.VoidCallback? onCancel;

  /// Displays the confirmation dialog and returns true if confirmed, false otherwise.
  static Future<bool?> show({
    required material.BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
    material.IconData? icon,
    bool barrierDismissible = true,
  }) {
    return showAppDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => QueryaConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
        icon: icon,
        onConfirm: () => material.Navigator.of(ctx).pop(true),
        onCancel: () => material.Navigator.of(ctx).pop(false),
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = context.colors;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;

    final effectiveIconData = icon ??
        (isDestructive
            ? material.Icons.warning_amber_rounded
            : material.Icons.help_outline_rounded);

    final iconColor = isDestructive
        ? (workbench?.destructive ?? cs.destructive)
        : (workbench?.accent ?? cs.primary);

    return QueryaModalDialog(
      title: material.Text(title),
      description: material.Text(message),
      icon: material.Icon(effectiveIconData),
      iconColor: iconColor,
      actions: [
        QueryaButton.ghost(
          label: cancelLabel,
          size: QueryaControlSize.lg,
          onPressed:
              onCancel ?? () => material.Navigator.of(context).pop(false),
        ),
        if (isDestructive)
          QueryaButton.destructive(
            label: confirmLabel,
            size: QueryaControlSize.lg,
            onPressed:
                onConfirm ?? () => material.Navigator.of(context).pop(true),
          )
        else
          QueryaButton.primary(
            label: confirmLabel,
            size: QueryaControlSize.lg,
            onPressed:
                onConfirm ?? () => material.Navigator.of(context).pop(true),
          ),
      ],
    );
  }
}
