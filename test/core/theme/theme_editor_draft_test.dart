import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_from_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/theme_editor_draft.dart';

void main() {
  group('ThemeEditorDraft', () {
    test('fromQueryaTheme captures MVP colors', () {
      const theme = QueryaTheme.darkDefault;
      final draft = ThemeEditorDraft.fromQueryaTheme(
        id: 'querya-dark',
        name: 'Querya Dark',
        isDark: true,
        theme: theme,
      );

      expect(draft.shadcnColors['primary'],
          formatVsCodeColor(theme.colorScheme.primary));
      expect(draft.editorColors['background'],
          formatVsCodeColor(theme.editor.background));
      expect(draft.editorColors['canvas'],
          formatVsCodeColor(theme.workbench.canvas));
    });

    test('setColor updates manifest and round-trips export', () {
      final raw = File('test/fixtures/themes/querya_custom_dark.json')
          .readAsStringSync();
      final source = QueryaThemeManifest.fromJsonString(raw);
      final draft = ThemeEditorDraft.fromManifest(source);

      draft.setColorHex(
        themeEditorMvpColorFields.first,
        '#FF00AA',
      );

      final exported = draft.toExportJsonString();
      final reparsed = QueryaThemeManifest.fromJsonString(exported);
      expect(reparsed.shadcnColors['primary'], '#ff00aa');

      final theme = queryaThemeFromManifest(reparsed);
      expect(theme.colorScheme.primary, parseQueryaThemeColor('#FF00AA'));
    });

    test('forExport assigns new id for read-only built-in source', () {
      final draft = ThemeEditorDraft.fromQueryaTheme(
        id: 'querya-dark',
        name: 'Querya Dark',
        isDark: true,
        theme: QueryaTheme.darkDefault,
        readOnlySource: true,
      );

      final exported = draft.forExport();
      expect(exported.id, 'querya-dark-edited');
      expect(exported.name, 'Querya Dark (edited)');

      final json =
          jsonDecode(exported.toExportJsonString()) as Map<String, dynamic>;
      expect(json['schema'], queryaThemeSchemaV1);
      expect(json['id'], 'querya-dark-edited');
    });
  });
}
