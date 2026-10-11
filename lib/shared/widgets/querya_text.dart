import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';

/// Text styles for a `Text` (or anything that renders text) through the
/// ambient [material.DefaultTextStyle], replacing shadcn's `TextExtension`
/// (#1465).
///
/// Sizes are the ones the app has always used (12 / 14 / 16 / 18); the UI scale
/// reaches them through the `MediaQuery` text scaler, so nothing is scaled here.
/// Colours come from the theme's colour scheme.
///
/// ```dart
/// Text('Connections').semiBold().small()
/// Text('No rows').muted()
/// ```
extension QueryaTextStyles on material.Widget {
  /// 12 px.
  material.Widget xSmall() => _fontSize(12);

  /// 14 px.
  material.Widget small() => _fontSize(14);

  /// 16 px.
  material.Widget base() => _fontSize(16);

  /// 18 px.
  material.Widget large() => _fontSize(18);

  /// Weight 500.
  material.Widget medium() => _weight(material.FontWeight.w500);

  /// Weight 600.
  material.Widget semiBold() => _weight(material.FontWeight.w600);

  /// Weight 700.
  material.Widget bold() => _weight(material.FontWeight.w700);

  /// One line, cut with an ellipsis.
  material.Widget ellipsis() => _QueryaStyledText(
        overflow: material.TextOverflow.ellipsis,
        maxLines: 1,
        child: this,
      );

  /// The muted foreground colour.
  material.Widget muted() => _QueryaStyledText(
        style: (context) =>
            material.TextStyle(color: context.colors.mutedForeground),
        child: this,
      );

  /// The standard foreground colour.
  material.Widget foreground() => _QueryaStyledText(
        style: (context) =>
            material.TextStyle(color: context.colors.foreground),
        child: this,
      );

  material.Widget _fontSize(double size) => _QueryaStyledText(
        style: (_) => material.TextStyle(fontSize: size),
        child: this,
      );

  material.Widget _weight(material.FontWeight weight) => _QueryaStyledText(
        style: (_) => material.TextStyle(fontWeight: weight),
        child: this,
      );
}

class _QueryaStyledText extends material.StatelessWidget {
  const _QueryaStyledText({
    required this.child,
    this.style,
    this.overflow,
    this.maxLines,
  });

  final material.Widget child;
  final material.TextStyle Function(material.BuildContext context)? style;
  final material.TextOverflow? overflow;
  final int? maxLines;

  @override
  material.Widget build(material.BuildContext context) {
    return material.DefaultTextStyle.merge(
      style: style?.call(context),
      overflow: overflow,
      maxLines: maxLines,
      child: child,
    );
  }
}
