import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';

/// Preset sizes for the [QueryaSpinner] indicator.
enum QueryaSpinnerSize {
  /// Small (14px diameter, strokeWidth 2.0) — for buttons, tree rows, and inline badges.
  sm(14, 2.0),

  /// Medium (20px diameter, strokeWidth 2.5) — for toolbars, dialogs, and panels.
  md(20, 2.5),

  /// Large (32px diameter, strokeWidth 3.0) — for full page loaders and tab overviews.
  lg(32, 3.0);

  const QueryaSpinnerSize(this.dimension, this.strokeWidth);

  final double dimension;
  final double strokeWidth;
}

/// Theme-aware progress indicator with size presets and optional inline label.
class QueryaSpinner extends material.StatelessWidget {
  const QueryaSpinner({
    super.key,
    this.size = QueryaSpinnerSize.md,
    this.customDimension,
    this.strokeWidth,
    this.color,
    this.label,
  });

  /// Preset size: [QueryaSpinnerSize.sm], [QueryaSpinnerSize.md], or [QueryaSpinnerSize.lg].
  final QueryaSpinnerSize size;

  /// Custom dimension (width and height in px) overriding preset.
  final double? customDimension;

  /// Custom stroke width overriding preset.
  final double? strokeWidth;

  /// Custom spinner color. If omitted, uses the active theme's accent color.
  final material.Color? color;

  /// Optional label displayed to the right of the spinner.
  final String? label;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;

    final dimension = customDimension ?? size.dimension;
    final stroke = strokeWidth ?? size.strokeWidth;
    final effectiveColor = color ?? workbench?.accent ?? cs.primary;

    final spinner = material.SizedBox(
      width: dimension,
      height: dimension,
      child: material.CircularProgressIndicator(
        strokeWidth: stroke,
        valueColor: material.AlwaysStoppedAnimation<material.Color>(effectiveColor),
      ),
    );

    if (label == null || label!.isEmpty) {
      return spinner;
    }

    return material.Row(
      mainAxisSize: material.MainAxisSize.min,
      crossAxisAlignment: material.CrossAxisAlignment.center,
      children: [
        spinner,
        const Gap(8),
        material.Text(
          label!,
          style: material.TextStyle(
            fontSize: size == QueryaSpinnerSize.sm ? 11 : 12,
            color: workbench?.mutedForeground ?? cs.mutedForeground,
          ),
        ),
      ],
    );
  }
}
