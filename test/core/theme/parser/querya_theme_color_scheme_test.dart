import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_color_scheme.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('colorSchemeFromQueryaThemeColors', () {
    test('full fixture maps custom shadcn values', () {
      final raw = File('test/fixtures/themes/querya_custom_dark.json')
          .readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);
      final scheme = colorSchemeFromQueryaThemeColors(
        colors: manifest.shadcnColors,
        fallback: QueryaTheme.darkDefault,
      );

      expect(scheme.brightness, Brightness.dark);
      expect(scheme.background, parseQueryaThemeColor('#101014'));
      expect(scheme.foreground, parseQueryaThemeColor('#E2E8F0'));
      expect(scheme.primary, parseQueryaThemeColor('#38BDF8'));
      expect(scheme.accent, parseQueryaThemeColor('#6366F1'));
      expect(scheme.chart3, parseQueryaThemeColor('#F472B6'));
      expect(scheme.chart5, parseQueryaThemeColor('#34D399'));
    });

    test('missing keys preserve fallback colorScheme values', () {
      final scheme = colorSchemeFromQueryaThemeColors(
        colors: const {'primary': '#FF00AA'},
        fallback: QueryaTheme.darkDefault,
      );
      final fallback = QueryaTheme.darkDefault.colorScheme;

      expect(scheme.primary, parseQueryaThemeColor('#FF00AA'));
      expect(scheme.background, fallback.background);
      expect(scheme.foreground, fallback.foreground);
      expect(scheme.border, fallback.border);
      expect(scheme.chart1, fallback.chart1);
    });

    test('invalid optional color uses fallback value', () {
      final fallback = QueryaTheme.darkDefault.colorScheme;
      final scheme = colorSchemeFromQueryaThemeColors(
        colors: const {
          'primary': 'not-a-color',
          'background': '#101014',
        },
        fallback: QueryaTheme.darkDefault,
      );

      expect(scheme.primary, fallback.primary);
      expect(scheme.background, parseQueryaThemeColor('#101014'));
    });

    test('chart colors fall back when omitted', () {
      final fallback = QueryaTheme.lightDefault.colorScheme;
      final scheme = colorSchemeFromQueryaThemeColors(
        colors: const {'background': '#FFFFFF'},
        fallback: QueryaTheme.lightDefault,
      );

      expect(scheme.background, parseQueryaThemeColor('#FFFFFF'));
      expect(scheme.chart1, fallback.chart1);
      expect(scheme.chart2, fallback.chart2);
      expect(scheme.chart3, fallback.chart3);
      expect(scheme.chart4, fallback.chart4);
      expect(scheme.chart5, fallback.chart5);
    });

    test('brightness comes from fallback theme, not colors map', () {
      final scheme = colorSchemeFromQueryaThemeColors(
        colors: const {
          'background': '#101014',
          'foreground': '#E2E8F0',
        },
        fallback: QueryaTheme.lightDefault,
      );

      expect(scheme.brightness, Brightness.light);
      expect(scheme.background, parseQueryaThemeColor('#101014'));
    });
  });
}
