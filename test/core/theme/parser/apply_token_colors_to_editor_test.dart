import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/apply_token_colors_to_editor.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';

void main() {
  test('applyTokenColorsToEditor maps comment and keyword scopes', () {
    const rules = [
      TokenColorRule(scopes: ['comment'], foreground: '#111111'),
      TokenColorRule(scopes: ['keyword'], foreground: '#222222'),
      TokenColorRule(scopes: ['string'], foreground: '#333333'),
    ];

    const base = QueryaEditorTheme.darkDefault;
    final next = applyTokenColorsToEditor(base, rules);

    expect(next.comment, const Color(0xFF111111));
    expect(next.keyword, const Color(0xFF222222));
    expect(next.string, const Color(0xFF333333));
    expect(next.foreground, base.foreground);
  });

  test('empty rules returns unchanged editor theme', () {
    const base = QueryaEditorTheme.darkDefault;
    expect(applyTokenColorsToEditor(base, const []), base);
  });
}
