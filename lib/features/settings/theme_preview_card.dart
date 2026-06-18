import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown_tokens.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Result of an async theme preview load for [ThemePreviewCard].
sealed class ThemePreviewResult {
  const ThemePreviewResult();

  const factory ThemePreviewResult.theme(QueryaTheme theme) =
      ThemePreviewSuccess;
  const factory ThemePreviewResult.error(String message) = ThemePreviewFailure;
  const factory ThemePreviewResult.loading() = ThemePreviewLoading;
}

final class ThemePreviewSuccess extends ThemePreviewResult {
  const ThemePreviewSuccess(this.theme);
  final QueryaTheme theme;
}

final class ThemePreviewFailure extends ThemePreviewResult {
  const ThemePreviewFailure(this.message);
  final String message;
}

final class ThemePreviewLoading extends ThemePreviewResult {
  const ThemePreviewLoading();
}

/// Compact visual preview for a [QueryaTheme] without applying it app-wide.
class ThemePreviewCard extends material.StatelessWidget {
  const ThemePreviewCard({
    super.key,
    this.theme,
    this.errorMessage,
    this.isLoading = false,
    this.label,
  });

  final QueryaTheme? theme;
  final String? errorMessage;
  final bool isLoading;
  final String? label;

  @override
  material.Widget build(material.BuildContext context) {
    final appScheme = Theme.of(context).colorScheme;
    final radius = context.scaled(QueryaDropdownTokens.menuBorderRadius);

    if (isLoading) {
      return _shell(
        context: context,
        radius: radius,
        borderColor: appScheme.border,
        child: material.Row(
          children: [
            material.SizedBox(
              width: context.scaled(14),
              height: context.scaled(14),
              child: material.CircularProgressIndicator(
                strokeWidth: 2,
                color: appScheme.mutedForeground,
              ),
            ),
            material.SizedBox(width: context.scaled(8)),
            material.Text(
              'Loading preview…',
              style: material.TextStyle(
                fontSize: context.scaled(12),
                color: appScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return _shell(
        context: context,
        radius: radius,
        borderColor: appScheme.destructive.withValues(alpha: 0.45),
        child: material.Text(
          errorMessage!,
          maxLines: 2,
          overflow: material.TextOverflow.ellipsis,
          style: material.TextStyle(
            fontSize: context.scaled(12),
            color: appScheme.destructive,
          ),
        ),
      );
    }

    final previewTheme = theme;
    if (previewTheme == null) {
      return _shell(
        context: context,
        radius: radius,
        borderColor: appScheme.border,
        child: material.Text(
          'Hover a theme to preview.',
          style: material.TextStyle(
            fontSize: context.scaled(12),
            color: appScheme.mutedForeground,
          ),
        ),
      );
    }

    final scheme = previewTheme.colorScheme;
    final workbench = previewTheme.workbench;
    final editor = previewTheme.editor;

    return _shell(
      context: context,
      radius: radius,
      borderColor: appScheme.border,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          if (label != null && label!.isNotEmpty)
            material.Padding(
              padding: material.EdgeInsets.only(bottom: context.scaled(6)),
              child: material.Text(
                label!,
                maxLines: 1,
                overflow: material.TextOverflow.ellipsis,
                style: material.TextStyle(
                  fontSize: context.scaled(11),
                  fontWeight: material.FontWeight.w600,
                  color: appScheme.popoverForeground,
                ),
              ),
            ),
          material.Row(
            children: [
              _Swatch(color: scheme.background, label: 'Bg'),
              material.SizedBox(width: context.scaled(6)),
              _Swatch(color: workbench.surface, label: 'Surface'),
              material.SizedBox(width: context.scaled(6)),
              _Swatch(color: scheme.primary, label: 'Primary'),
              material.SizedBox(width: context.scaled(6)),
              _Swatch(color: workbench.accent, label: 'Accent'),
              material.SizedBox(width: context.scaled(8)),
              material.Expanded(
                child: material.Container(
                  padding: material.EdgeInsets.symmetric(
                    horizontal: context.scaled(8),
                    vertical: context.scaled(6),
                  ),
                  decoration: material.BoxDecoration(
                    color: workbench.surface,
                    borderRadius: material.BorderRadius.circular(radius),
                    border: material.Border.all(
                      color: scheme.border.withValues(alpha: 0.7),
                    ),
                  ),
                  child: material.Text(
                    'Sample text',
                    maxLines: 1,
                    overflow: material.TextOverflow.ellipsis,
                    style: material.TextStyle(
                      fontSize: context.scaled(12),
                      color: scheme.foreground,
                    ),
                  ),
                ),
              ),
            ],
          ),
          material.SizedBox(height: context.scaled(6)),
          material.Container(
            height: context.scaled(10),
            width: double.infinity,
            decoration: material.BoxDecoration(
              color: editor.background,
              borderRadius: material.BorderRadius.circular(radius),
              border: material.Border.all(
                color: scheme.border.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  material.Widget _shell({
    required material.BuildContext context,
    required double radius,
    required Color borderColor,
    required material.Widget child,
  }) {
    return material.Container(
      width: double.infinity,
      padding: material.EdgeInsets.all(context.scaled(8)),
      decoration: material.BoxDecoration(
        color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.12),
        borderRadius: material.BorderRadius.circular(radius),
        border: material.Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

class _Swatch extends material.StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  material.Widget build(material.BuildContext context) {
    final radius = context.scaled(4);
    return material.Column(
      children: [
        material.Container(
          width: context.scaled(18),
          height: context.scaled(18),
          decoration: material.BoxDecoration(
            color: color,
            borderRadius: material.BorderRadius.circular(radius),
            border: material.Border.all(
              color: material.Colors.black.withValues(alpha: 0.12),
            ),
          ),
        ),
        material.SizedBox(height: context.scaled(2)),
        material.Text(
          label,
          style: material.TextStyle(
            fontSize: context.scaled(9),
            color: Theme.of(context).colorScheme.mutedForeground,
          ),
        ),
      ],
    );
  }
}
