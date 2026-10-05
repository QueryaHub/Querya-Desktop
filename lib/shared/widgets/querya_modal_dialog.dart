import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';

import 'app_dialog.dart';
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
    final cs = Theme.of(context).colorScheme;
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
                  const Gap(14),
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
                        const Gap(4),
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
                    child: material.IconButton(
                      icon: const material.Icon(material.Icons.close_rounded, size: 18),
                      splashRadius: 16,
                      padding: material.EdgeInsets.zero,
                      constraints: const material.BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      color: cs.mutedForeground,
                      hoverColor: cs.muted.withValues(alpha: 0.3),
                      onPressed: onClose ?? () => Navigator.of(context).pop(),
                    ),
                  ),
              ],
            ),

            // Content
            if (content != null) ...[
              const Gap(16),
              content!,
            ],

            // Actions
            if (actions != null && actions!.isNotEmpty) ...[
              const Gap(20),
              material.Align(
                alignment: material.Alignment.centerRight,
                child: material.Wrap(
                  alignment: material.WrapAlignment.end,
                  crossAxisAlignment: material.WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions!,
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
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;

    final effectiveIconData = icon ??
        (isDestructive
            ? material.Icons.warning_amber_rounded
            : material.Icons.help_outline_rounded);

    final iconColor = isDestructive
        ? (workbench?.destructive ?? cs.destructive)
        : (workbench?.accent ?? cs.primary);

    return QueryaModalDialog(
      title: Text(title),
      description: Text(message),
      icon: material.Icon(effectiveIconData),
      iconColor: iconColor,
      actions: [
        OutlineButton(
          onPressed: onCancel ?? () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        if (isDestructive)
          DestructiveButton(
            onPressed: onConfirm ?? () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          )
        else
          PrimaryButton(
            onPressed: onConfirm ?? () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
      ],
    );
  }
}
