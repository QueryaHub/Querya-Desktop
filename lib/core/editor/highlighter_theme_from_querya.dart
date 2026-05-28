import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

/// Builds a [HighlighterTheme] from [QueryaEditorTheme] token colors.
HighlighterTheme highlighterThemeFromQueryaEditor(QueryaEditorTheme editor) {
  final wrapper = TextStyle(
    color: editor.foreground,
    fontFamily: editor.fontFamily,
    fontSize: editor.fontSize,
  );

  final config = jsonEncode({
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
        'scope': ['constant.numeric', 'number'],
        'settings': {'foreground': _hex(editor.number)},
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

  return HighlighterTheme.fromConfiguration(config, wrapper);
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
