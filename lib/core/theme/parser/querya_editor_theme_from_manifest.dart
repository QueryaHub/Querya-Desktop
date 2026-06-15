import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../querya_editor_theme.dart';
import 'color_parser.dart';

const _knownEditorColorKeys = {
  'background',
  'foreground',
  'lineHighlight',
  'selection',
  'lineNumber',
  'bracketMatch',
  'widgetBorder',
  'comment',
  'keyword',
  'string',
  'number',
  'operator',
  'function',
  'type',
};

/// Builds [QueryaEditorTheme] from Querya custom `editor_colors`.
///
/// Missing keys and invalid optional colors fall back to [fallback].
/// Workbench-related keys in the same map are ignored here (handled separately).
QueryaEditorTheme editorThemeFromQueryaColors({
  required Map<String, String> colors,
  required QueryaEditorTheme fallback,
}) {
  if (kDebugMode) {
    for (final key in colors.keys) {
      if (!_knownEditorColorKeys.contains(key)) {
        debugPrint('Querya theme: ignored editor_colors key "$key"');
      }
    }
  }

  Color pick(String key, Color defaultValue) {
    final raw = colors[key];
    if (raw == null) return defaultValue;
    try {
      return parseQueryaThemeColor(raw);
    } on FormatException {
      if (kDebugMode) {
        debugPrint('Querya theme: invalid editor_colors."$key": $raw');
      }
      return defaultValue;
    }
  }

  Color? pickOptional(String key, Color? defaultValue) {
    final raw = colors[key];
    if (raw == null) return defaultValue;
    try {
      return parseQueryaThemeColor(raw);
    } on FormatException {
      if (kDebugMode) {
        debugPrint('Querya theme: invalid editor_colors."$key": $raw');
      }
      return defaultValue;
    }
  }

  return fallback.copyWith(
    background: pick('background', fallback.background),
    foreground: pick('foreground', fallback.foreground),
    lineHighlight: pick('lineHighlight', fallback.lineHighlight),
    selection: pick('selection', fallback.selection),
    lineNumber: pick('lineNumber', fallback.lineNumber),
    bracketMatch: pick('bracketMatch', fallback.bracketMatch),
    widgetBorder: pickOptional('widgetBorder', fallback.widgetBorder),
    comment: pick('comment', fallback.comment),
    keyword: pick('keyword', fallback.keyword),
    string: pick('string', fallback.string),
    number: pick('number', fallback.number),
    operator: pick('operator', fallback.operator),
    function: pick('function', fallback.function),
    type: pick('type', fallback.type),
  );
}
