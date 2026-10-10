import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Fixed metrics for [QueryaDropdown] — single source of truth for dropdown UI.
abstract final class QueryaDropdownTokens {
  /// Compact desktop trigger height (content is vertically centered).
  static const double triggerHeight = QueryaControlMetrics.heightLg;

  static const double triggerPaddingHorizontal = 12.0;

  static const double triggerChevronGap = 8.0;

  static const double triggerChevronSize = 18.0;

  static const material.Offset menuAlignmentOffset = material.Offset(0, 4.0);

  static const double menuMaxHeight = 300.0;

  static const int menuScrollItemThreshold = 8;

  static const double menuBorderRadius = QueryaControlMetrics.radius;

  /// Soft popover shadow (shadcn-like): thin border + low elevation.
  static const double menuElevation = 2.0;

  static const material.Color menuShadowColor = material.Color(0x1F000000);

  static const material.EdgeInsets menuPadding =
      material.EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0);

  static const double menuItemHeight = QueryaControlMetrics.heightMd;

  static const material.EdgeInsets menuItemPadding =
      material.EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0);

  /// Compact variant for toolbars / panel headers.
  static const double compactTriggerHeight = QueryaControlMetrics.heightSm;

  static const double compactTriggerPaddingHorizontal = 8.0;

  static const double compactFontSize = QueryaControlMetrics.fontSm;

  static const double compactMenuItemHeight = QueryaControlMetrics.heightSm;

  static const double fontSize = QueryaControlMetrics.fontLg;

  static const double lineHeight = 1.25;

  static const double selectedCheckSize = 16.0;

  static const double selectedCheckSlotWidth = 18.0;

  /// The control size a dropdown draws at: an explicit [size], else
  /// [QueryaControlSize.sm] for [compact], else [QueryaControlSize.lg].
  static QueryaControlSize sizeFor({
    bool compact = false,
    QueryaControlSize? size,
  }) =>
      size ?? (compact ? QueryaControlSize.sm : QueryaControlSize.lg);

  static double scaledTriggerHeight(material.BuildContext context,
          {bool compact = false, QueryaControlSize? size}) =>
      context.scaled(sizeFor(compact: compact, size: size).height);

  static double scaledFontSize(material.BuildContext context,
          {bool compact = false, QueryaControlSize? size}) =>
      context.scaled(sizeFor(compact: compact, size: size).fontSize);

  /// Menu rows follow the trigger down to [QueryaControlSize.sm] but never
  /// grow past [QueryaControlSize.md].
  static double scaledMenuItemHeight(material.BuildContext context,
          {bool compact = false, QueryaControlSize? size}) =>
      context.scaled(
        sizeFor(compact: compact, size: size) == QueryaControlSize.sm
            ? compactMenuItemHeight
            : menuItemHeight,
      );

  static double scaledMenuMaxHeight(material.BuildContext context) =>
      context.scaled(menuMaxHeight);

  static material.EdgeInsets scaledTriggerPadding(
          material.BuildContext context,
          {bool compact = false,
          QueryaControlSize? size}) =>
      material.EdgeInsets.symmetric(
        horizontal: context.scaled(
          sizeFor(compact: compact, size: size) == QueryaControlSize.sm
              ? compactTriggerPaddingHorizontal
              : triggerPaddingHorizontal,
        ),
      );

  static material.TextStyle triggerTextStyle(
    material.BuildContext context,
    material.Color color, {
    bool compact = false,
    QueryaControlSize? size,
  }) {
    final fontSize = scaledFontSize(context, compact: compact, size: size);
    return material.TextStyle(
      fontSize: fontSize,
      height: lineHeight,
      fontWeight: material.FontWeight.w500,
      color: color,
    );
  }

  static material.TextStyle menuItemTextStyle(
    material.BuildContext context,
    material.Color color, {
    required bool selected,
    bool compact = false,
    QueryaControlSize? size,
  }) {
    final fontSize = scaledFontSize(context, compact: compact, size: size);
    return material.TextStyle(
      fontSize: fontSize,
      height: lineHeight,
      fontWeight:
          selected ? material.FontWeight.w600 : material.FontWeight.w400,
      color: color,
    );
  }
}

/// Uniform label column width in [PreferencesFieldRow].
const double kPreferencesLabelWidth = 152.0;
