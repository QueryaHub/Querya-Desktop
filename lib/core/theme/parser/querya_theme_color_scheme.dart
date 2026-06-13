import 'package:flutter/foundation.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../querya_theme.dart';
import 'color_parser.dart';

const _knownShadcnColorKeys = {
  'background',
  'foreground',
  'card',
  'cardForeground',
  'popover',
  'popoverForeground',
  'primary',
  'primaryForeground',
  'secondary',
  'secondaryForeground',
  'muted',
  'mutedForeground',
  'accent',
  'accentForeground',
  'destructive',
  'destructiveForeground',
  'border',
  'input',
  'ring',
  'chart1',
  'chart2',
  'chart3',
  'chart4',
  'chart5',
};

/// Builds a shadcn [ColorScheme] from Querya custom `shadcn_colors`.
///
/// Missing keys and invalid optional colors fall back to [fallback.colorScheme].
/// [ColorScheme.brightness] always comes from [fallback], not from [colors].
ColorScheme colorSchemeFromQueryaThemeColors({
  required Map<String, String> colors,
  required QueryaTheme fallback,
}) {
  final base = fallback.colorScheme;

  if (kDebugMode) {
    for (final key in colors.keys) {
      if (!_knownShadcnColorKeys.contains(key)) {
        debugPrint('Querya theme: ignored shadcn_colors key "$key"');
      }
    }
  }

  Color pick(String key, Color defaultValue) {
    final raw = colors[key];
    if (raw == null) return defaultValue;
    try {
      return parseQueryaThemeColor(raw);
    } on FormatException {
      if (kDebugMode) {
        debugPrint('Querya theme: invalid shadcn_colors."$key": $raw');
      }
      return defaultValue;
    }
  }

  final destructive = pick('destructive', base.destructive);
  // querya.theme.v1 still maps this key; shadcn marks the ColorScheme field legacy.
  // ignore: deprecated_member_use
  final destructiveForeground =
      pick('destructiveForeground', base.destructiveForeground);

  return ColorScheme(
    brightness: base.brightness,
    background: pick('background', base.background),
    foreground: pick('foreground', base.foreground),
    card: pick('card', base.card),
    cardForeground: pick('cardForeground', base.cardForeground),
    popover: pick('popover', base.popover),
    popoverForeground: pick('popoverForeground', base.popoverForeground),
    primary: pick('primary', base.primary),
    primaryForeground: pick('primaryForeground', base.primaryForeground),
    secondary: pick('secondary', base.secondary),
    secondaryForeground: pick('secondaryForeground', base.secondaryForeground),
    muted: pick('muted', base.muted),
    mutedForeground: pick('mutedForeground', base.mutedForeground),
    accent: pick('accent', base.accent),
    accentForeground: pick('accentForeground', base.accentForeground),
    destructive: destructive,
    // ignore: deprecated_member_use
    destructiveForeground: destructiveForeground,
    border: pick('border', base.border),
    input: pick('input', base.input),
    ring: pick('ring', base.ring),
    chart1: pick('chart1', base.chart1),
    chart2: pick('chart2', base.chart2),
    chart3: pick('chart3', base.chart3),
    chart4: pick('chart4', base.chart4),
    chart5: pick('chart5', base.chart5),
  );
}
