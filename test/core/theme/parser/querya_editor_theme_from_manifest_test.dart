import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/parser/querya_editor_theme_from_manifest.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';

void main() {
  group('editorThemeFromQueryaColors', () {
    test('full fixture maps custom editor values', () {
      final raw = File('test/fixtures/themes/querya_custom_dark.json')
          .readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);
      final editor = editorThemeFromQueryaColors(
        colors: manifest.editorColors,
        fallback: QueryaTheme.darkDefault.editor,
      );

      expect(editor.background, parseQueryaThemeColor('#0F1117'));
      expect(editor.foreground, parseQueryaThemeColor('#E2E8F0'));
      expect(editor.selection, parseQueryaThemeColor('#264F78'));
      expect(editor.lineNumber, parseQueryaThemeColor('#64748B'));
      expect(editor.widgetBorder, parseQueryaThemeColor('#38BDF866'));
      expect(editor.keyword, parseQueryaThemeColor('#569CD6'));
    });

    test('minimal fixture falls back for missing editor fields', () {
      final raw = File('test/fixtures/themes/querya_custom_minimal.json')
          .readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);
      final fallback = QueryaTheme.darkDefault.editor;
      final editor = editorThemeFromQueryaColors(
        colors: manifest.editorColors,
        fallback: fallback,
      );

      expect(editor.background, parseQueryaThemeColor('#010203'));
      expect(editor.foreground, fallback.foreground);
      expect(editor.selection, fallback.selection);
      expect(editor.comment, fallback.comment);
      expect(editor.widgetBorder, fallback.widgetBorder);
    });

    test('invalid optional color uses fallback value', () {
      final fallback = QueryaTheme.darkDefault.editor;
      final editor = editorThemeFromQueryaColors(
        colors: const {
          'background': '#0F1117',
          'selection': 'bad-color',
          'keyword': 'ZZZZZZ',
        },
        fallback: fallback,
      );

      expect(editor.background, parseQueryaThemeColor('#0F1117'));
      expect(editor.selection, fallback.selection);
      expect(editor.keyword, fallback.keyword);
    });
  });
}
