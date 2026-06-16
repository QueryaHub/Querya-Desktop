import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_color_scheme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('QueryaTheme.lightDefault', () {
    test('colorScheme differs from dark preset', () {
      final light = QueryaTheme.lightDefault.colorScheme;
      final dark = QueryaTheme.darkDefault.colorScheme;
      expect(light.background, isNot(dark.background));
      expect(light.foreground, isNot(dark.foreground));
      expect(light.brightness, Brightness.light);
    });

    test('QueryaColorScheme.light matches lightDefault', () {
      expect(
        QueryaColorScheme.light.background,
        QueryaTheme.lightDefault.colorScheme.background,
      );
    });

    test('primary text on canvas meets WCAG AA contrast (4.5:1)', () {
      final w = QueryaTheme.lightDefault.workbench;
      final ratio = contrastRatio(w.canvas, const Color(0xFF0F172A));
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('editor foreground on editor background meets WCAG AA', () {
      final e = QueryaTheme.lightDefault.editor;
      final ratio = contrastRatio(e.background, e.foreground);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('toShadcnThemeData uses light brightness', () {
      final td = QueryaTheme.lightDefault.toShadcnThemeData();
      expect(td.brightness, Brightness.light);
      expect(td.colorScheme.primary, QueryaTheme.lightDefault.workbench.accent);
    });
  });
}

/// Relative luminance contrast per WCAG 2.1.
double contrastRatio(Color a, Color b) {
  final l1 = _relativeLuminance(a);
  final l2 = _relativeLuminance(b);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color c) {
  double channel(double v) {
    final normalized = v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return normalized;
  }

  final r = channel(c.r);
  final g = channel(c.g);
  final b = channel(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
