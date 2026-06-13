import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/parser/querya_workbench_theme_from_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';

void main() {
  group('workbenchThemeFromQueryaColors', () {
    test('full fixture maps custom workbench values', () {
      final raw =
          File('test/fixtures/themes/querya_custom_dark.json').readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);
      final workbench = workbenchThemeFromQueryaColors(
        colors: manifest.editorColors,
        fallback: QueryaTheme.darkDefault.workbench,
      );

      expect(workbench.canvas, parseQueryaThemeColor('#09090B'));
      expect(workbench.surface, parseQueryaThemeColor('#111827'));
      expect(workbench.sidebarBackground, parseQueryaThemeColor('#0B0F19'));
      expect(workbench.editorBackground, parseQueryaThemeColor('#0F1117'));
      expect(workbench.accent, parseQueryaThemeColor('#38BDF8'));
      expect(workbench.gitModified, parseQueryaThemeColor('#FBBF24'));
      expect(workbench.gitUntracked, parseQueryaThemeColor('#34D399'));
    });

    test('minimal fixture falls back for missing workbench fields', () {
      final raw = File('test/fixtures/themes/querya_custom_minimal.json')
          .readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);
      final fallback = QueryaTheme.darkDefault.workbench;
      final workbench = workbenchThemeFromQueryaColors(
        colors: manifest.editorColors,
        fallback: fallback,
      );

      expect(workbench.canvas, fallback.canvas);
      expect(workbench.surface, fallback.surface);
      expect(workbench.accent, fallback.accent);
      expect(workbench.gitModified, fallback.gitModified);
    });

    test('invalid optional color uses fallback value', () {
      final fallback = QueryaTheme.darkDefault.workbench;
      final workbench = workbenchThemeFromQueryaColors(
        colors: const {
          'canvas': '#09090B',
          'accent': 'not-a-color',
          'gitModified': 'ZZZZZZ',
        },
        fallback: fallback,
      );

      expect(workbench.canvas, parseQueryaThemeColor('#09090B'));
      expect(workbench.accent, fallback.accent);
      expect(workbench.gitModified, fallback.gitModified);
    });

    test('does not map editor background key to workbench canvas', () {
      final fallback = QueryaTheme.darkDefault.workbench;
      final workbench = workbenchThemeFromQueryaColors(
        colors: const {'background': '#010203'},
        fallback: fallback,
      );

      expect(workbench.canvas, fallback.canvas);
      expect(workbench.editorBackground, fallback.editorBackground);
    });
  });
}
