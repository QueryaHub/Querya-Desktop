import 'package:flutter/material.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

import 'syntax_highlight_isolate.dart';

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

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final brightness = Theme.of(context).brightness;
    final highlighter = brightness == Brightness.light
        ? lightHighlighter
        : darkHighlighter;
    final themeConfig = brightness == Brightness.light
        ? lightThemeConfig
        : darkThemeConfig;

    if (text.length < kSyntaxHighlightIsolateThreshold) {
      return TextSpan(
        style: style,
        children: [highlighter.highlight(text)],
      );
    }

    if (_cachedText == text &&
        _cachedBrightness == brightness &&
        _cachedSpan != null) {
      return TextSpan(style: style, children: [_cachedSpan!]);
    }

    _scheduleIsolateHighlight(
      text: text,
      brightness: brightness,
      themeConfig: themeConfig,
      style: style,
    );

    if (_cachedSpan != null && _cachedText == text) {
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
    });
  }

  @override
  void dispose() {
    _highlightGeneration++;
    super.dispose();
  }
}
