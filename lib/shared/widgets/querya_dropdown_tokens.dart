import 'package:flutter/material.dart' as material;

/// Fixed metrics for [QueryaDropdown] — single source of truth for dropdown UI.
abstract final class QueryaDropdownTokens {
  /// Compact desktop trigger height.
  static const double triggerHeight = 32.0;

  static const material.EdgeInsets triggerPadding =
      material.EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0);

  static const double triggerChevronGap = 8.0;

  static const double triggerChevronSize = 18.0;

  static const material.Offset menuAlignmentOffset = material.Offset(0, 4.0);

  static const double menuMaxHeight = 300.0;

  static const int menuScrollItemThreshold = 8;

  static const double menuBorderRadius = 6.0;

  static const double menuElevation = 8.0;

  static const double menuShadowBlurRadius = 8.0;

  static const material.Color menuShadowColor = material.Color(0x42000000);

  static const material.EdgeInsets menuPadding =
      material.EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0);

  static const double menuItemHeight = 28.0;

  static const material.EdgeInsets menuItemPadding =
      material.EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0);

  static const double menuItemMinWidth = 180.0;

  static const double fontSize = 13.0;

  static const double selectedCheckSize = 16.0;

  static const double selectedCheckSlotWidth = 18.0;

  static const int hoverAnimationMs = 120;
}
