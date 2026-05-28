import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_from_vscode.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('theme fixtures', () {
    test('dracula_tokens.json parses colors and tokenColors', () {
      final raw =
          File('test/fixtures/themes/dracula_tokens.json').readAsStringSync();
      final manifest = VsCodeThemeManifest.fromJsonString(raw);
      expect(manifest.name, 'Dracula Fixture');
      expect(manifest.isDark, isTrue);
      expect(manifest.colors['editor.background'], '#282a36');
      expect(manifest.tokenColors.length, 4);
    });

    test('one_dark.json builds QueryaTheme with editor background', () {
      final raw = File('test/fixtures/themes/one_dark.json').readAsStringSync();
      final manifest = VsCodeThemeManifest.fromJsonString(raw);
      final theme = buildQueryaThemeFromVsCodeManifest(
        manifest,
        fallback: QueryaTheme.darkDefault,
      );
      expect(theme.workbench.editorBackground, const Color(0xFF282C34));
      expect(theme.tokenColors.length, 3);
      expect(theme.editor.comment, const Color(0xFF5C6370));
    });

    test('invalid-trailing-comma.jsonc parses after JSONC strip', () {
      final raw = File('test/fixtures/themes/invalid-trailing-comma.jsonc')
          .readAsStringSync();
      final manifest = VsCodeThemeManifest.fromJsonString(raw);
      expect(manifest.colors['editor.background'], '#282c34');
      expect(manifest.tokenColors.single.scopes, ['comment']);
    });
  });
}
