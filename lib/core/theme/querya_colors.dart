import 'dart:ui';

/// Design tokens aligned with [design-front] mockups (near-black canvas, cyan accent).
///
/// Canonical semantic mapping lives in [QueryaColorScheme]; these are named aliases
/// for documentation and for a few widgets that need the raw accent (e.g. glows).
abstract class QueryaColors {
  QueryaColors._();

  /// Main app background — pure black on reference hero.
  static const Color canvas = Color(0xFF000000);

  /// Elevated surface (cards, mock window chrome).
  static const Color surface = Color(0xFF0C0C0C);

  /// Brand accent (CTAs, tree icons, focus ring).
  static const Color accentCyan = Color(0xFF22D3EE);

  /// Text / icons on filled primary buttons.
  static const Color onAccent = Color(0xFF0A0A0A);

  /// Hairline borders on dark UI.
  static const Color borderSubtle = Color(0xFF27272A);

  /// Secondary label tone (body muted on mockups).
  static const Color mutedLabel = Color(0xFF94A3B8);
}
