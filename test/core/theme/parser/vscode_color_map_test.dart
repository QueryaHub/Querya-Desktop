import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_from_vscode.dart';
import 'package:querya_desktop/core/theme/parser/vscode_color_map.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('kVsCodeColorMap', () {
    test('documents every mapped key in supported list', () {
      for (final key in kVsCodeColorMap.keys) {
        expect(kSupportedVsCodeColorKeys, contains(key));
      }
    });
  });

  group('buildQueryaThemeFromVsCodeManifest', () {
    Future<String> fixture(String name) async {
      final path = 'test/fixtures/themes/$name';
      return File(path).readAsString();
    }

    test('dark_subset fixture maps workbench and editor', () async {
      final src = await fixture('dark_subset.json');
      final manifest = VsCodeThemeManifest.fromJsonString(src);
      final theme = buildQueryaThemeFromVsCodeManifest(manifest);

      expect(manifest.isDark, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.workbench.editorBackground, const Color(0xFF1E1E1E));
      expect(theme.workbench.sidebarBackground, const Color(0xFF252526));
      expect(theme.editor.foreground, const Color(0xFFD4D4D4));
      expect(theme.workbench.canvas, const Color(0xFF007ACC));
      expect(theme.workbench.accent, const Color(0xFF007FD4));
      expect(theme.workbench.gitModified, const Color(0xFFE2C08D));
      expect(theme.workbench.gitUntracked, const Color(0xFF73C991));
      expect(theme.colorScheme.foreground, const Color(0xFFD4D4D4));
      expect(theme.editor.background, const Color(0xFF1E1E1E));
    });

    test('editor.selectionBackground maps to editor.selection', () async {
      const src = '''
{
  "type": "dark",
  "colors": {
    "editor.selectionBackground": "#123456"
  }
}
''';
      final manifest = VsCodeThemeManifest.fromJsonString(src);
      final theme = buildQueryaThemeFromVsCodeManifest(manifest);
      expect(theme.editor.selection, const Color(0xFF123456));
    });

    test('light_subset fixture uses light brightness', () async {
      final src = await fixture('light_subset.json');
      final manifest = VsCodeThemeManifest.fromJsonString(src);
      final theme = buildQueryaThemeFromVsCodeManifest(manifest);

      expect(manifest.isLight, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.workbench.editorBackground, const Color(0xFFFFFFFF));
      expect(theme.workbench.sidebarBackground, const Color(0xFFF3F3F3));
      // `input.background` and `panel.background` both map to surface; last wins.
      expect(theme.workbench.surface, const Color(0xFFFFFFFF));
    });

    test('unknown keys are reported and defaults kept for unmapped tokens',
        () async {
      final src = await fixture('with_unknown_keys.json');
      final manifest = VsCodeThemeManifest.fromJsonString(src);
      final unknown = <String>[];
      final theme = buildQueryaThemeFromVsCodeManifest(
        manifest,
        onUnknownColorKey: unknown.add,
      );

      expect(unknown, contains('titleBar.activeBackground'));
      expect(unknown, contains('workbench.colorCustomizations.unsupported'));
      expect(theme.workbench.editorBackground, const Color(0xFF2D2D30));
      expect(
        theme.workbench.destructive,
        QueryaTheme.darkDefault.workbench.destructive,
      );
    });

    test('missing keys fall back to dark default', () async {
      const src = '''
{
  "type": "dark",
  "colors": {
    "editor.background": "#111111"
  }
}
''';
      final manifest = VsCodeThemeManifest.fromJsonString(src);
      final theme = buildQueryaThemeFromVsCodeManifest(manifest);

      expect(theme.workbench.editorBackground, const Color(0xFF111111));
      expect(
        theme.workbench.accent,
        QueryaTheme.darkDefault.workbench.accent,
      );
    });
  });
}
