import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

import 'highlighter_theme_from_querya.dart';
import 'querya_code_language.dart';

/// Global syntax highlighter setup for [QueryaCodeEditor].
abstract final class SyntaxHighlightService {
  static bool _initialized = false;
  static String? _sqlGrammarJson;
  static String? _jsonGrammarJson;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await Highlighter.initialize(['sql', 'json']);
    _sqlGrammarJson = await rootBundle.loadString(
      'packages/syntax_highlight/grammars/sql.json',
    );
    _jsonGrammarJson = await rootBundle.loadString(
      'packages/syntax_highlight/grammars/json.json',
    );
    _initialized = true;
  }

  static bool get isInitialized => _initialized;

  static String grammarJsonFor(QueryaCodeLanguage language) {
    _assertInitialized();
    return switch (language) {
      QueryaCodeLanguage.sql => _sqlGrammarJson!,
      QueryaCodeLanguage.json => _jsonGrammarJson!,
      QueryaCodeLanguage.plain => _sqlGrammarJson!,
    };
  }

  static Highlighter createHighlighter({
    required QueryaCodeLanguage language,
    required QueryaEditorTheme editorTheme,
    required Brightness brightness,
    List<TokenColorRule> tokenColors = const [],
  }) {
    _assertInitialized();
    final lang = switch (language) {
      QueryaCodeLanguage.sql => 'sql',
      QueryaCodeLanguage.json => 'json',
      QueryaCodeLanguage.plain => 'sql',
    };
    final theme = highlighterThemeFromQueryaEditor(
      editorTheme,
      tokenColors: tokenColors,
    );
    return Highlighter(language: lang, theme: theme);
  }

  static HighlighterPair createPair({
    required QueryaCodeLanguage language,
    required QueryaTheme queryaTheme,
  }) {
    final tokenColors = queryaTheme.tokenColors;
    return HighlighterPair(
      language: language,
      editorTheme: queryaTheme.editor,
      tokenColors: tokenColors,
      lightThemeConfig: highlighterThemeConfigJson(
        queryaTheme.editor,
        tokenColors: tokenColors,
      ),
      darkThemeConfig: highlighterThemeConfigJson(
        queryaTheme.editor,
        tokenColors: tokenColors,
      ),
      grammarJson: grammarJsonFor(language),
      light: createHighlighter(
        language: language,
        editorTheme: queryaTheme.editor,
        brightness: Brightness.light,
        tokenColors: tokenColors,
      ),
      dark: createHighlighter(
        language: language,
        editorTheme: queryaTheme.editor,
        brightness: Brightness.dark,
        tokenColors: tokenColors,
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
  const HighlighterPair({
    required this.light,
    required this.dark,
    required this.language,
    required this.editorTheme,
    required this.tokenColors,
    required this.lightThemeConfig,
    required this.darkThemeConfig,
    required this.grammarJson,
  });

  final Highlighter light;
  final Highlighter dark;
  final QueryaCodeLanguage language;
  final QueryaEditorTheme editorTheme;
  final List<TokenColorRule> tokenColors;
  final String lightThemeConfig;
  final String darkThemeConfig;
  final String grammarJson;

  Highlighter forBrightness(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  String themeConfigFor(Brightness brightness) =>
      brightness == Brightness.light ? lightThemeConfig : darkThemeConfig;
}
