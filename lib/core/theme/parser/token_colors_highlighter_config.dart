import 'dart:convert';

import 'package:flutter/material.dart';

import '../querya_editor_theme.dart';
import 'vscode_theme_manifest.dart';

/// Builds `syntax_highlight` theme JSON from VS Code `tokenColors`.
String buildHighlighterConfigFromTokenColors(
  List<TokenColorRule> tokenColors,
  Color fallbackForeground,
) {
  final settings = <Map<String, dynamic>>[];

  for (final rule in tokenColors) {
    final style = <String, dynamic>{};
    if (rule.foreground != null) style['foreground'] = rule.foreground;
    if (rule.background != null) style['background'] = rule.background;
    if (rule.fontStyle != null) style['fontStyle'] = rule.fontStyle;
    if (style.isEmpty) continue;

    settings.add({
      'scope': rule.scopes.length == 1 ? rule.scopes.single : rule.scopes,
      'settings': style,
    });
  }

  settings.add({
    'settings': {'foreground': _hex(fallbackForeground)},
  });

  return jsonEncode({'settings': settings});
}

String buildDefaultEditorHighlighterConfig(QueryaEditorTheme editor) {
  return jsonEncode({
    'settings': [
      {
        'scope': [
          'comment',
          'comment.line',
          'comment.block',
        ],
        'settings': {'foreground': _hex(editor.comment)},
      },
      {
        'scope': [
          'keyword',
          'keyword.control',
          'keyword.operator',
          'storage.type',
        ],
        'settings': {'foreground': _hex(editor.keyword)},
      },
      {
        'scope': [
          'string',
          'string.quoted',
          'string.quoted.single',
          'string.quoted.double',
        ],
        'settings': {'foreground': _hex(editor.string)},
      },
      {
        'scope': [
          'constant.numeric',
          'constant.numeric.json',
          'number',
        ],
        'settings': {'foreground': _hex(editor.number)},
      },
      {
        'scope': [
          'support.type.property-name',
          'support.type.property-name.json',
        ],
        'settings': {'foreground': _hex(editor.type)},
      },
      {
        'scope': [
          'constant.language',
          'constant.language.json',
        ],
        'settings': {'foreground': _hex(editor.keyword)},
      },
      {
        'scope': ['entity.name.function', 'support.function'],
        'settings': {'foreground': _hex(editor.function)},
      },
      {
        'scope': ['entity.name.type', 'support.type'],
        'settings': {'foreground': _hex(editor.type)},
      },
      {
        'scope': ['constant.language', 'variable.language'],
        'settings': {'foreground': _hex(editor.keyword)},
      },
      {
        'settings': {'foreground': _hex(editor.foreground)},
      },
    ],
  });
}

String _hex(Color c) {
  final a = (c.a * 255).round().clamp(0, 255);
  final r = (c.r * 255).round().clamp(0, 255);
  final g = (c.g * 255).round().clamp(0, 255);
  final b = (c.b * 255).round().clamp(0, 255);
  if (a < 255) {
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}'
        '${a.toRadixString(16).padLeft(2, '0')}';
  }
  return '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
}
