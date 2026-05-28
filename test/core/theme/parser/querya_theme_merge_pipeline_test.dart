import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_from_vscode.dart';
import 'package:querya_desktop/core/theme/parser/vscode_colors_merge.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('theme merge pipeline', () {
    test('default → imported → user overrides', () {
      const defaultLayer = {
        'editor.background': '#1e1e1e',
        'sideBar.background': '#252526',
      };
      const importedLayer = {
        'editor.background': '#2d2d30',
        'sideBar.background': '#333333',
      };
      const userLayer = {
        'sideBar.background': '#ff0000',
      };

      final merged = mergeVsCodeColorLayers([
        defaultLayer,
        importedLayer,
        userLayer,
      ]);

      final theme = buildQueryaThemeFromVsCodeColors(
        brightness: Brightness.dark,
        colors: merged,
        fallback: QueryaTheme.darkDefault,
      );

      expect(theme.workbench.editorBackground, const Color(0xFF2D2D30));
      expect(theme.workbench.sidebarBackground, const Color(0xFFFF0000));
    });

    test('manifest import then user override on same key', () {
      const src = '''
{
  "type": "dark",
  "colors": {
    "editor.background": "#1e1e1e"
  }
}
''';
      final imported = VsCodeThemeManifest.fromJsonString(src).colors;
      final merged = mergeVsCodeColorLayers([
        imported,
        {'editor.background': '#abcdef'},
      ]);
      final theme = buildQueryaThemeFromVsCodeColors(
        brightness: Brightness.dark,
        colors: merged,
        fallback: QueryaTheme.darkDefault,
      );
      expect(theme.workbench.editorBackground, const Color(0xFFABCDEF));
    });
  });
}
