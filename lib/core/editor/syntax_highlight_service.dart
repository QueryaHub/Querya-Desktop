import 'package:flutter/material.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

import 'highlighter_theme_from_querya.dart';
import 'querya_code_language.dart';

/// Global syntax highlighter setup for [QueryaCodeEditor].
abstract final class SyntaxHighlightService {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await Highlighter.initialize(['sql', 'json']);
    _initialized = true;
  }

  static bool get isInitialized => _initialized;

  static Highlighter createHighlighter({
    required QueryaCodeLanguage language,
    required QueryaEditorTheme editorTheme,
    required Brightness brightness,
  }) {
    _assertInitialized();
    final lang = switch (language) {
      QueryaCodeLanguage.sql => 'sql',
      QueryaCodeLanguage.json => 'json',
      QueryaCodeLanguage.plain => 'sql',
    };
    final theme = highlighterThemeFromQueryaEditor(editorTheme);
    return Highlighter(language: lang, theme: theme);
  }

  static HighlighterPair createPair({
    required QueryaCodeLanguage language,
    required QueryaTheme queryaTheme,
  }) {
    return HighlighterPair(
      light: createHighlighter(
        language: language,
        editorTheme: queryaTheme.editor,
        brightness: Brightness.light,
      ),
      dark: createHighlighter(
        language: language,
        editorTheme: queryaTheme.editor,
        brightness: Brightness.dark,
      ),
    );
  }

  static void _assertInitialized() {
    assert(
      _initialized,
      'Call SyntaxHighlightService.ensureInitialized() before use',
    );
  }
}

/// Light/dark highlighters for Material [Theme] brightness switching.
class HighlighterPair {
  const HighlighterPair({required this.light, required this.dark});

  final Highlighter light;
  final Highlighter dark;

  Highlighter forBrightness(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;
}
