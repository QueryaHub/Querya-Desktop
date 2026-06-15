import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_from_manifest.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';

void main() {
  group('queryaThemeFromManifest', () {
    test('full dark fixture builds dark QueryaTheme', () {
      final raw =
          File('test/fixtures/themes/querya_custom_dark.json').readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);
      final theme = queryaThemeFromManifest(manifest);

      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, parseQueryaThemeColor('#38BDF8'));
      expect(theme.workbench.canvas, parseQueryaThemeColor('#09090B'));
      expect(theme.editor.background, parseQueryaThemeColor('#0F1117'));
      expect(theme.editor.selection, parseQueryaThemeColor('#264F78'));
    });

    test('full light fixture builds light QueryaTheme', () {
      final raw =
          File('test/fixtures/themes/querya_custom_light.json').readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);
      final theme = queryaThemeFromManifest(manifest);

      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.background, parseQueryaThemeColor('#F8FAFC'));
      expect(theme.workbench.surface, parseQueryaThemeColor('#FFFFFF'));
      expect(theme.editor.foreground, parseQueryaThemeColor('#1E293B'));
    });

    test('preserves tokenColors from manifest', () {
      final raw =
          File('test/fixtures/themes/querya_custom_dark.json').readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);
      final theme = queryaThemeFromManifest(manifest);

      expect(theme.tokenColors.length, manifest.tokenColors.length);
      expect(theme.tokenColors.first.scopes, ['comment', 'comment.line']);
    });

    test('minimal fixture falls back to preset defaults', () {
      final raw = File('test/fixtures/themes/querya_custom_minimal.json')
          .readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);
      final theme = queryaThemeFromManifest(manifest);
      const fallback = QueryaTheme.darkDefault;

      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, parseQueryaThemeColor('#FF00AA'));
      expect(theme.editor.background, parseQueryaThemeColor('#010203'));
      expect(theme.editor.foreground, fallback.editor.foreground);
      expect(theme.workbench.canvas, fallback.workbench.canvas);
      expect(theme.tokenColors, isEmpty);
    });

    test('does not create ThemeData', () {
      final raw =
          File('test/fixtures/themes/querya_custom_dark.json').readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);

      expect(queryaThemeFromManifest(manifest), isA<QueryaTheme>());
    });
  });
}
