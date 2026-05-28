import 'dart:math' as math;
import 'dart:ui';

/// Relative luminance (WCAG) for [color].
double colorLuminance(Color color) {
  double channel(double linear) {
    return linear <= 0.03928
        ? linear / 12.92
        : math.pow((linear + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG contrast ratio between [foreground] and [background].
double contrastRatio(Color foreground, Color background) {
  final l1 = colorLuminance(foreground);
  final l2 = colorLuminance(background);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Picks [candidate] when readable on [background], else a softened [fallback].
Color legibleSecondaryLabel({
  required Color candidate,
  required Color background,
  required Color fallback,
  double minRatio = 4.5,
}) {
  if (contrastRatio(candidate, background) >= minRatio) {
    return candidate;
  }
  return fallback.withValues(alpha: 0.72);
}
