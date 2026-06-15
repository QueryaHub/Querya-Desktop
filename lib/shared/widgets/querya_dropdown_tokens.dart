import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/ui_scale.dart';

/// Fixed metrics for [QueryaDropdown] — single source of truth for dropdown UI.
abstract final class QueryaDropdownTokens {
  /// Compact desktop trigger height (content is vertically centered).
  static const double triggerHeight = 36.0;

  static const double triggerPaddingHorizontal = 12.0;

  static const double triggerChevronGap = 8.0;

  static const double triggerChevronSize = 18.0;

  static const material.Offset menuAlignmentOffset = material.Offset(0, 4.0);

  static const double menuMaxHeight = 300.0;

  static const int menuScrollItemThreshold = 8;

  static const double menuBorderRadius = 6.0;

  static const double menuElevation = 8.0;

  static const material.Color menuShadowColor = material.Color(0x42000000);

  static const material.EdgeInsets menuPadding =
      material.EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0);

  static const double menuItemHeight = 32.0;

  static const material.EdgeInsets menuItemPadding =
      material.EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0);

  static const double fontSize = 14.0;

  static const double lineHeight = 1.25;

  static const double selectedCheckSize = 16.0;

  static const double selectedCheckSlotWidth = 18.0;

  static double scaledTriggerHeight(material.BuildContext context) =>
      context.scaled(triggerHeight);

  static double scaledFontSize(material.BuildContext context) =>
      context.scaled(fontSize);

  static double scaledMenuItemHeight(material.BuildContext context) =>
      context.scaled(menuItemHeight);

  static double scaledMenuMaxHeight(material.BuildContext context) =>
      context.scaled(menuMaxHeight);

  static material.EdgeInsets scaledTriggerPadding(material.BuildContext context) =>
      material.EdgeInsets.symmetric(
        horizontal: context.scaled(triggerPaddingHorizontal),
      );

  static material.TextStyle triggerTextStyle(
    material.BuildContext context,
    material.Color color,
  ) {
    final size = scaledFontSize(context);
    return material.TextStyle(
      fontSize: size,
      height: lineHeight,
      fontWeight: material.FontWeight.w500,
      color: color,
    );
  }

  static material.TextStyle menuItemTextStyle(
    material.BuildContext context,
    material.Color color, {
    required bool selected,
  }) {
    final size = scaledFontSize(context);
    return material.TextStyle(
      fontSize: size,
      height: lineHeight,
      fontWeight: selected ? material.FontWeight.w600 : material.FontWeight.w400,
      color: color,
    );
  }
}

/// Uniform label column width in [PreferencesFieldRow].
const double kPreferencesLabelWidth = 152.0;
