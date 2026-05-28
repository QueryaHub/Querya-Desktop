import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';

void main() {
  group('VsCodeThemeManifest', () {
    test('parses minimal dark theme with JSONC', () {
      const src = '''
{
  // theme
  "name": "Test Dark",
  "type": "dark",
  "colors": {
    "editor.background": "#1e1e1e",
    "sideBar.background": "#252526",
  },
  "tokenColors": [
    {
      "scope": "comment",
      "settings": { "foreground": "#6A9955" }
    },
    {
      "scope": ["keyword", "storage.type"],
      "settings": { "foreground": "#569CD6", "fontStyle": "italic" }
    },
  ],
}
''';
      final m = VsCodeThemeManifest.fromJsonString(src);
      expect(m.name, 'Test Dark');
      expect(m.isDark, isTrue);
      expect(m.colors['editor.background'], '#1e1e1e');
      expect(m.tokenColors.length, 2);
      expect(m.tokenColors.first.scopes, ['comment']);
      expect(m.tokenColors.first.foreground, '#6A9955');
      expect(m.tokenColors[1].scopes, ['keyword', 'storage.type']);
    });

    test('throws on invalid JSON', () {
      expect(
        () => VsCodeThemeManifest.fromJsonString('{ not json }'),
        throwsA(isA<VsCodeThemeParseException>()),
      );
    });
  });
}
