import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The colours the app's widgets read: surfaces, text, accent, borders and
/// the chart series (#1730, epic #1465).
///
/// Holds exactly the fields `lib/` uses of shadcn's `ColorScheme`, under the
/// same names, so a caller moves from `Theme.of(context).colorScheme` to
/// `context.colors` without other changes. While the app still runs on
/// shadcn's shell the values are read from the shadcn scheme and converted in
/// `querya_color_scheme.dart`, the one place that knows both; after #1735 this
/// is the source.
@immutable
class QueryaUiColors {
  const QueryaUiColors({
    required this.brightness,
    required this.background,
    required this.foreground,
    required this.card,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.destructive,
    required this.destructiveForeground,
    required this.border,
    required this.ring,
    required this.chart1,
    required this.chart2,
    required this.chart3,
    required this.chart4,
    required this.chart5,
  });

  final Brightness brightness;

  /// Page background.
  final Color background;

  /// Main text and icons.
  final Color foreground;

  /// Raised surfaces: cards, panels.
  final Color card;

  /// Menus, dropdowns and other floating surfaces, and their text.
  final Color popover;
  final Color popoverForeground;

  /// The accent: filled buttons, selection, links; and what sits on it.
  final Color primary;
  final Color primaryForeground;

  /// Quiet filled surfaces (secondary buttons) and their text.
  final Color secondary;
  final Color secondaryForeground;

  /// Subdued backgrounds (hover, chips) and secondary text.
  final Color muted;
  final Color mutedForeground;

  /// Hover and highlight background.
  final Color accent;

  /// Errors and destructive actions, and what sits on them.
  final Color destructive;
  final Color destructiveForeground;

  /// Hairlines and control outlines; the focus ring.
  final Color border;
  final Color ring;

  /// Chart series.
  final Color chart1;
  final Color chart2;
  final Color chart3;
  final Color chart4;
  final Color chart5;

  static QueryaUiColors lerp(QueryaUiColors a, QueryaUiColors b, double t) {
    Color l(Color x, Color y) => Color.lerp(x, y, t)!;
    return QueryaUiColors(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      background: l(a.background, b.background),
      foreground: l(a.foreground, b.foreground),
      card: l(a.card, b.card),
      popover: l(a.popover, b.popover),
      popoverForeground: l(a.popoverForeground, b.popoverForeground),
      primary: l(a.primary, b.primary),
      primaryForeground: l(a.primaryForeground, b.primaryForeground),
      secondary: l(a.secondary, b.secondary),
      secondaryForeground: l(a.secondaryForeground, b.secondaryForeground),
      muted: l(a.muted, b.muted),
      mutedForeground: l(a.mutedForeground, b.mutedForeground),
      accent: l(a.accent, b.accent),
      destructive: l(a.destructive, b.destructive),
      destructiveForeground:
          l(a.destructiveForeground, b.destructiveForeground),
      border: l(a.border, b.border),
      ring: l(a.ring, b.ring),
      chart1: l(a.chart1, b.chart1),
      chart2: l(a.chart2, b.chart2),
      chart3: l(a.chart3, b.chart3),
      chart4: l(a.chart4, b.chart4),
      chart5: l(a.chart5, b.chart5),
    );
  }

  List<Object> get _props => [
        brightness, background, foreground, card, popover, popoverForeground,
        primary, primaryForeground, secondary, secondaryForeground, muted,
        mutedForeground, accent, destructive, destructiveForeground, border,
        ring, chart1, chart2, chart3, chart4, chart5,
      ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! QueryaUiColors) return false;
    return listEquals(_props, other._props);
  }

  @override
  int get hashCode => Object.hashAll(_props);
}
