import 'dart:async';

import 'package:flutter/material.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

import 'syntax_highlight_isolate.dart';

/// Debounce delay before scheduling syntax highlight work.
const Duration kSyntaxHighlightDebounce = Duration(milliseconds: 100);

/// [TextEditingController] that applies [Highlighter] in [buildTextSpan].
class QueryaHighlightController extends TextEditingController {
  QueryaHighlightController({
    super.text,
    required this.language,
    required this.lightHighlighter,
    required this.darkHighlighter,
    required this.lightThemeConfig,
    required this.darkThemeConfig,
    required this.grammarJson,
    required this.wrapperColor,
  });

  final QueryaCodeLanguage language;
  final Highlighter lightHighlighter;
  final Highlighter darkHighlighter;
  final String lightThemeConfig;
  final String darkThemeConfig;
  final String grammarJson;
  final Color wrapperColor;

  TextSpan? _cachedSpan;
  String? _cachedText;
  Brightness? _cachedBrightness;
  int _highlightGeneration = 0;
  Timer? _debounceTimer;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final brightness = Theme.of(context).brightness;
    final themeConfig =
        brightness == Brightness.light ? lightThemeConfig : darkThemeConfig;

    if (_cachedText == text &&
        _cachedBrightness == brightness &&
        _cachedSpan != null) {
      return TextSpan(style: style, children: [_cachedSpan!]);
    }

    if (text.length < kSyntaxHighlightIsolateThreshold) {
      final highlighter =
          brightness == Brightness.light ? lightHighlighter : darkHighlighter;
      try {
        final span = highlighter.highlight(text);
        _cachedSpan = span;
        _cachedText = text;
        _cachedBrightness = brightness;
        _debounceTimer?.cancel();
        return TextSpan(style: style, children: [span]);
      } catch (_) {
        // Fall back to isolate or unhighlighted text on unexpected parsing error.
      }
    }

    _scheduleIsolateHighlight(
      text: text,
      brightness: brightness,
      themeConfig: themeConfig,
      style: style,
    );

    if (_cachedSpan != null) {
      return TextSpan(style: style, children: [_cachedSpan!]);
    }

    return TextSpan(style: style, text: text);
  }

  void _scheduleIsolateHighlight({
    required String text,
    required Brightness brightness,
    required String themeConfig,
    required TextStyle? style,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(kSyntaxHighlightDebounce, () {
      _runIsolateHighlight(
        text: text,
        brightness: brightness,
        themeConfig: themeConfig,
        style: style,
      );
    });
  }

  void _runIsolateHighlight({
    required String text,
    required Brightness brightness,
    required String themeConfig,
    required TextStyle? style,
  }) {
    final generation = ++_highlightGeneration;
    final lang = switch (language) {
      QueryaCodeLanguage.sql => 'sql',
      QueryaCodeLanguage.json => 'json',
      QueryaCodeLanguage.plain => 'sql',
    };

    highlightOffMainThread(
      SyntaxHighlightJob(
        code: text,
        language: lang,
        themeConfigJson: themeConfig,
        grammarJson: grammarJson,
        wrapperArgb: wrapperColor.toARGB32(),
      ),
    ).then((segments) {
      if (generation != _highlightGeneration) return;
      _cachedSpan = segmentsToTextSpan(segments, baseStyle: style);
      _cachedText = text;
      _cachedBrightness = brightness;
      notifyListeners();
    }).catchError((Object error, StackTrace stack) {
      // In case of syntax highlight failure, keep cached or plain text without crashing.
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _highlightGeneration++;
    super.dispose();
  }
}
