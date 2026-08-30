import 'package:flutter/material.dart';
import 'package:querya_desktop/core/theme/parser/token_colors_highlighter_config.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

/// Builds a [HighlighterTheme] from [QueryaEditorTheme] and optional VS Code rules.
HighlighterTheme highlighterThemeFromQueryaEditor(
  QueryaEditorTheme editor, {
  List<TokenColorRule> tokenColors = const [],
}) {
  final wrapper = TextStyle(
    color: editor.foreground,
    fontFamily: editor.fontFamily,
    fontFamilyFallback: editor.fontFamilyFallback,
    fontSize: editor.fontSize,
  );

  final config = tokenColors.isNotEmpty
      ? buildHighlighterConfigFromTokenColors(tokenColors, editor.foreground)
      : buildDefaultEditorHighlighterConfig(editor);

  return HighlighterTheme.fromConfiguration(config, wrapper);
}

/// JSON config for isolate/off-thread highlighting.
String highlighterThemeConfigJson(
  QueryaEditorTheme editor, {
  List<TokenColorRule> tokenColors = const [],
}) {
  return tokenColors.isNotEmpty
      ? buildHighlighterConfigFromTokenColors(tokenColors, editor.foreground)
      : buildDefaultEditorHighlighterConfig(editor);
}
