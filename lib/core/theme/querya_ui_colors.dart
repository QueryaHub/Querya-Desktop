import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The colours the app's widgets read: surfaces, text, accent, borders and
/// the chart series (#1730, epic #1465).
///
/// The theme's colour scheme (the names are shadcn's, which the app grew up
/// on): [QueryaTheme.colors], read by widgets as `context.colors` (#1730,
/// #1735).
@immutable
class QueryaUiColors {
  const QueryaUiColors({
    required this.brightness,
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.border,
    required this.input,
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

  /// Raised surfaces: cards, panels, and their text.
  final Color card;
  final Color cardForeground;

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

  /// Hover and highlight background, and its text.
  final Color accent;
  final Color accentForeground;

  /// Errors and destructive actions, and what sits on them.
  final Color destructive;
  final Color destructiveForeground;

  /// Hairlines, control outlines and the outline of an input; the focus ring.
  final Color border;
  final Color input;
  final Color ring;

  /// Chart series.
  final Color chart1;
  final Color chart2;
  final Color chart3;
  final Color chart4;
  final Color chart5;

  QueryaUiColors copyWith({
    Brightness? brightness,
    Color? background,
    Color? foreground,
    Color? card,
    Color? cardForeground,
    Color? popover,
    Color? popoverForeground,
    Color? primary,
    Color? primaryForeground,
    Color? secondary,
    Color? secondaryForeground,
    Color? muted,
    Color? mutedForeground,
    Color? accent,
    Color? accentForeground,
    Color? destructive,
    Color? destructiveForeground,
    Color? border,
    Color? input,
    Color? ring,
    Color? chart1,
    Color? chart2,
    Color? chart3,
    Color? chart4,
    Color? chart5,
  }) =>
      QueryaUiColors(
        brightness: brightness ?? this.brightness,
        background: background ?? this.background,
        foreground: foreground ?? this.foreground,
        card: card ?? this.card,
        cardForeground: cardForeground ?? this.cardForeground,
        popover: popover ?? this.popover,
        popoverForeground: popoverForeground ?? this.popoverForeground,
        primary: primary ?? this.primary,
        primaryForeground: primaryForeground ?? this.primaryForeground,
        secondary: secondary ?? this.secondary,
        secondaryForeground: secondaryForeground ?? this.secondaryForeground,
        muted: muted ?? this.muted,
        mutedForeground: mutedForeground ?? this.mutedForeground,
        accent: accent ?? this.accent,
        accentForeground: accentForeground ?? this.accentForeground,
        destructive: destructive ?? this.destructive,
        destructiveForeground:
            destructiveForeground ?? this.destructiveForeground,
        border: border ?? this.border,
        input: input ?? this.input,
        ring: ring ?? this.ring,
        chart1: chart1 ?? this.chart1,
        chart2: chart2 ?? this.chart2,
        chart3: chart3 ?? this.chart3,
        chart4: chart4 ?? this.chart4,
        chart5: chart5 ?? this.chart5,
      );

  static QueryaUiColors lerp(QueryaUiColors a, QueryaUiColors b, double t) {
    Color l(Color x, Color y) => Color.lerp(x, y, t)!;
    return QueryaUiColors(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      background: l(a.background, b.background),
      foreground: l(a.foreground, b.foreground),
      card: l(a.card, b.card),
      cardForeground: l(a.cardForeground, b.cardForeground),
      popover: l(a.popover, b.popover),
      popoverForeground: l(a.popoverForeground, b.popoverForeground),
      primary: l(a.primary, b.primary),
      primaryForeground: l(a.primaryForeground, b.primaryForeground),
      secondary: l(a.secondary, b.secondary),
      secondaryForeground: l(a.secondaryForeground, b.secondaryForeground),
      muted: l(a.muted, b.muted),
      mutedForeground: l(a.mutedForeground, b.mutedForeground),
      accent: l(a.accent, b.accent),
      accentForeground: l(a.accentForeground, b.accentForeground),
      destructive: l(a.destructive, b.destructive),
      destructiveForeground:
          l(a.destructiveForeground, b.destructiveForeground),
      border: l(a.border, b.border),
      input: l(a.input, b.input),
      ring: l(a.ring, b.ring),
      chart1: l(a.chart1, b.chart1),
      chart2: l(a.chart2, b.chart2),
      chart3: l(a.chart3, b.chart3),
      chart4: l(a.chart4, b.chart4),
      chart5: l(a.chart5, b.chart5),
    );
  }

  List<Object> get _props => [
        brightness, background, foreground, card, cardForeground, popover, popoverForeground,
        primary, primaryForeground, secondary, secondaryForeground, muted,
        mutedForeground, accent, accentForeground, destructive, destructiveForeground, border,
        input, ring, chart1, chart2, chart3, chart4, chart5,
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
