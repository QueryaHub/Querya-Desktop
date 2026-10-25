import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

import 'highlighter_theme_from_querya.dart';
import 'querya_code_language.dart';
import 'querya_highlight_controller.dart';

/// A TextMate grammar [json] that Dart's RegExp can run: a regex that starts
/// with the inline flag `(?i)` (Oniguruma) has no Dart form that works.
/// `(?i)` itself is rejected ("Invalid group"), and `(?i:a|b)` applies the
/// flag to the last alternative only (checked on Dart 3.13), so each ASCII
/// letter becomes a class instead: `select` -> `[sS][eE][lL]...`.
@visibleForTesting
String normalizeGrammarJson(String json) {
  Object? fix(Object? node) {
    if (node is List) return [for (final item in node) fix(item)];
    if (node is Map) {
      return {
        for (final entry in node.entries)
          entry.key: switch (entry.key) {
            'match' || 'begin' || 'end' || 'while'
                when entry.value is String =>
              _withoutInlineIgnoreCase(entry.value as String),
            _ => fix(entry.value),
          },
      };
    }
    return node;
  }

  return jsonEncode(fix(jsonDecode(json)));
}

/// [pattern] without a leading `(?i)`, with every ASCII letter outside
/// escapes and group syntax matching both cases. Other patterns are returned
/// as they are.
@visibleForTesting
String withoutInlineIgnoreCase(String pattern) =>
    _withoutInlineIgnoreCase(pattern);

String _withoutInlineIgnoreCase(String pattern) {
  if (!pattern.startsWith('(?i)')) return pattern;
  final src = pattern.substring(4);
  final out = StringBuffer();
  bool isLetter(String c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0);
  String swap(String c) =>
      c == c.toLowerCase() ? c.toUpperCase() : c.toLowerCase();

  var inClass = false;
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == r'\') {
      // An escape (`\b`, `\s`, `\.`): copied as it is.
      out.write(c);
      if (i + 1 < src.length) out.write(src[i + 1]);
      i += 2;
      continue;
    }
    if (inClass) {
      if (c == ']') {
        inClass = false;
        out.write(c);
      } else if (isLetter(c) &&
          i + 2 < src.length &&
          src[i + 1] == '-' &&
          isLetter(src[i + 2])) {
        // A range such as a-z also gets its other-case twin.
        out
          ..write('$c-${src[i + 2]}')
          ..write('${swap(c)}-${swap(src[i + 2])}');
        i += 3;
        continue;
      } else if (isLetter(c)) {
        out
          ..write(c)
          ..write(swap(c));
      } else {
        out.write(c);
      }
      i++;
      continue;
    }
    if (c == '[') {
      inClass = true;
      out.write(c);
      i++;
      if (i < src.length && src[i] == '^') {
        out.write('^');
        i++;
      }
      // A `]` right after `[` / `[^` is a literal member.
      if (i < src.length && src[i] == ']') {
        out.write(']');
        i++;
      }
      continue;
    }
    if (c == '(' && i + 1 < src.length && src[i + 1] == '?') {
      // Group syntax: `(?:`, `(?=`, `(?!`, `(?<=`, `(?<!`, `(?<name>`.
      var j = i + 2;
      if (j < src.length && src[j] == '<' && j + 1 < src.length) {
        if (src[j + 1] == '=' || src[j + 1] == '!') {
          j += 2;
        } else {
          j = src.indexOf('>', j) + 1;
          if (j == 0) j = src.length;
        }
      } else if (j < src.length) {
        j += 1;
      }
      out.write(src.substring(i, j));
      i = j;
      continue;
    }
    if (isLetter(c)) {
      out.write('[$c${swap(c)}]');
    } else {
      out.write(c);
    }
    i++;
  }
  return out.toString();
}

/// Global syntax highlighter setup for [QueryaCodeEditor].
abstract final class SyntaxHighlightService {
  static bool _initialized = false;
  static String? _sqlGrammarJson;
  static String? _jsonGrammarJson;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    // Not `Highlighter.initialize`: it compiles the grammars as shipped, and 17
    // of the 27 rules of the SQL one start with `(?i)`, which Dart's RegExp
    // rejects ("Invalid group"), so those rules were dropped and no SQL
    // keyword was ever coloured (#1814). The grammars are fixed first.
    _sqlGrammarJson = normalizeGrammarJson(await rootBundle.loadString(
      'packages/syntax_highlight/grammars/sql.json',
    ));
    _jsonGrammarJson = normalizeGrammarJson(await rootBundle.loadString(
      'packages/syntax_highlight/grammars/json.json',
    ));
    Highlighter.addLanguage('sql', _sqlGrammarJson!);
    Highlighter.addLanguage('json', _jsonGrammarJson!);
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
    final cacheKey = Object.hash(
      language,
      queryaTheme.editor,
      queryaTheme.tokenColorsHash,
    );
    final cached = _pairCache[cacheKey];
    if (cached != null) return cached;

    final pair = _buildPair(language: language, queryaTheme: queryaTheme);
    if (_pairCache.length >= _maxPairCacheEntries) {
      _pairCache.remove(_pairCache.keys.first);
    }
    _pairCache[cacheKey] = pair;
    return pair;
  }

  static const _maxPairCacheEntries = 12;
  static final Map<int, HighlighterPair> _pairCache = {};

  static HighlighterPair _buildPair({
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

  /// Creates a [QueryaHighlightController] initialized with highlighters and grammar for [language].
  /// If syntax highlighting is not initialized or [language] is plain, falls back to a plain [TextEditingController].
  static TextEditingController createHighlightController({
    required QueryaCodeLanguage language,
    String? text,
    QueryaTheme? queryaTheme,
  }) {
    if (!_initialized || language == QueryaCodeLanguage.plain) {
      return TextEditingController(text: text);
    }
    final theme = queryaTheme ?? QueryaTheme.darkDefault;
    final pair = createPair(language: language, queryaTheme: theme);
    return QueryaHighlightController(
      text: text,
      language: language,
      lightHighlighter: pair.light,
      darkHighlighter: pair.dark,
      lightThemeConfig: pair.lightThemeConfig,
      darkThemeConfig: pair.darkThemeConfig,
      grammarJson: pair.grammarJson,
      wrapperColor: theme.editor.foreground,
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
