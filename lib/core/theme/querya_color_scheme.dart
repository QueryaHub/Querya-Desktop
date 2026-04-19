import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'querya_colors.dart';

/// Dark [ColorScheme] for Querya desktop — matches [QueryaColors] tokens.
abstract class QueryaColorScheme {
  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    background: QueryaColors.canvas,
    foreground: Color(0xFFF8FAFC),
    card: QueryaColors.surface,
    cardForeground: Color(0xFFF8FAFC),
    popover: QueryaColors.surface,
    popoverForeground: Color(0xFFF8FAFC),
    primary: QueryaColors.accentCyan,
    primaryForeground: QueryaColors.onAccent,
    secondary: Color(0xFF18181B),
    secondaryForeground: Color(0xFFF8FAFC),
    muted: Color(0xFF18181B),
    mutedForeground: QueryaColors.mutedLabel,
    accent: Color(0xFF27272A),
    accentForeground: Color(0xFFF8FAFC),
    destructive: Color(0xFFEF4444),
    destructiveForeground: Color(0xFFF8FAFC),
    border: QueryaColors.borderSubtle,
    input: QueryaColors.borderSubtle,
    ring: QueryaColors.accentCyan,
    chart1: Color(0xFF2662D9),
    chart2: Color(0xFF2EB88A),
    chart3: Color(0xFFE88C30),
    chart4: Color(0xFFAF57DB),
    chart5: Color(0xFFE23670),
  );
}
