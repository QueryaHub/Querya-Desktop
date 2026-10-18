import 'package:shadcn_flutter/shadcn_flutter.dart' hide Gap, TextExtension;

import 'querya_theme.dart';
import 'querya_ui_colors.dart';

/// Shadcn [ColorScheme] presets — derived from [QueryaTheme] defaults.
abstract class QueryaColorScheme {
  static ColorScheme get dark => QueryaTheme.darkDefault.colorScheme;
  static ColorScheme get light => QueryaTheme.lightDefault.colorScheme;
}

final Expando<QueryaUiColors> _uiColorsCache = Expando();

/// The bridge between shadcn's scheme and [QueryaUiColors] while the app still
/// runs on shadcn's shell (#1730, epic #1465); it goes with #1735.
extension QueryaUiColorsFromShadcn on ColorScheme {
  /// The same colours as [QueryaUiColors] (cached per scheme instance).
  QueryaUiColors get uiColors => _uiColorsCache[this] ??= QueryaUiColors(
        brightness: brightness,
        background: background,
        foreground: foreground,
        card: card,
        popover: popover,
        popoverForeground: popoverForeground,
        primary: primary,
        primaryForeground: primaryForeground,
        secondary: secondary,
        secondaryForeground: secondaryForeground,
        muted: muted,
        mutedForeground: mutedForeground,
        accent: accent,
        destructive: destructive,
        destructiveForeground: destructiveForeground,
        border: border,
        ring: ring,
        chart1: chart1,
        chart2: chart2,
        chart3: chart3,
        chart4: chart4,
        chart5: chart5,
      );
}

extension QueryaUiColorsToShadcn on QueryaUiColors {
  /// A shadcn scheme for the widgets still on shadcn. The fields shadcn has
  /// and the app does not read follow the ones next to them, as every Querya
  /// theme sets them today: card and accent text are [foreground], the input
  /// outline is [border].
  ColorScheme toShadcn() => ColorScheme(
        brightness: brightness,
        background: background,
        foreground: foreground,
        card: card,
        cardForeground: foreground,
        popover: popover,
        popoverForeground: popoverForeground,
        primary: primary,
        primaryForeground: primaryForeground,
        secondary: secondary,
        secondaryForeground: secondaryForeground,
        muted: muted,
        mutedForeground: mutedForeground,
        accent: accent,
        accentForeground: foreground,
        destructive: destructive,
        destructiveForeground: destructiveForeground,
        border: border,
        input: border,
        ring: ring,
        chart1: chart1,
        chart2: chart2,
        chart3: chart3,
        chart4: chart4,
        chart5: chart5,
      );
}
