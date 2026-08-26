import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';

/// Computes the relative luminance of a color according to WCAG 2.1 specification.
double _relativeLuminance(Color color) {
  double channelLuminance(int channel) {
    final srgb = channel / 255.0;
    return srgb <= 0.04045 ? srgb / 12.92 : math.pow((srgb + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channelLuminance(color.red);
  final g = channelLuminance(color.green);
  final b = channelLuminance(color.blue);

  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Calculates the contrast ratio between two colors (ranging from 1.0 to 21.0).
double _contrastRatio(Color c1, Color c2) {
  final l1 = _relativeLuminance(c1);
  final l2 = _relativeLuminance(c2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('WCAG 2.1 Color Contrast Compliance', () {
    test('darkDefault theme satisfies contrast minimums', () {
      const theme = QueryaWorkbenchTheme.darkDefault;

      // Accent against canvas / surface
      final accentOnCanvas = _contrastRatio(theme.accent, theme.canvas);
      final accentOnSurface = _contrastRatio(theme.accent, theme.surface);

      expect(accentOnCanvas, greaterThanOrEqualTo(4.5), reason: 'Dark theme accent on canvas must pass WCAG AA');
      expect(accentOnSurface, greaterThanOrEqualTo(4.5), reason: 'Dark theme accent on surface must pass WCAG AA');

      // On-accent text against accent button background
      final onAccentRatio = _contrastRatio(theme.onAccent, theme.accent);
      expect(onAccentRatio, greaterThanOrEqualTo(4.5), reason: 'OnAccent on accent button must pass WCAG AA');
    });

    test('lightDefault theme satisfies contrast minimums (WCAG AA 4.5:1+)', () {
      const theme = QueryaWorkbenchTheme.lightDefault;

      // Accent against canvas / surface
      final accentOnCanvas = _contrastRatio(theme.accent, theme.canvas);
      final accentOnSurface = _contrastRatio(theme.accent, theme.surface);

      expect(accentOnCanvas, greaterThanOrEqualTo(4.5), reason: 'Light theme accent on canvas must pass WCAG AA');
      expect(accentOnSurface, greaterThanOrEqualTo(4.5), reason: 'Light theme accent on surface must pass WCAG AA');

      // On-accent text against accent button background
      final onAccentRatio = _contrastRatio(theme.onAccent, theme.accent);
      expect(onAccentRatio, greaterThanOrEqualTo(4.5), reason: 'Light theme onAccent text must pass WCAG AA');
    });
  });
}
