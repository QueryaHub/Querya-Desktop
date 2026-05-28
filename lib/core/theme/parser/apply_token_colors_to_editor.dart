import 'package:flutter/material.dart';

import '../querya_editor_theme.dart';
import 'token_style_resolver.dart';
import 'vscode_theme_manifest.dart';

/// Maps common TextMate scopes from [rules] onto [QueryaEditorTheme] fields.
QueryaEditorTheme applyTokenColorsToEditor(
  QueryaEditorTheme editor,
  List<TokenColorRule> rules,
) {
  if (rules.isEmpty) return editor;

  final resolver = TokenStyleResolver(
    rules: rules,
    defaultStyle: TextStyle(color: editor.foreground),
  );

  Color? colorFor(Iterable<String> scopes) {
    for (final scope in scopes) {
      final c = resolver.resolve(scope).color;
      if (c != null) return c;
    }
    return null;
  }

  return editor.copyWith(
    comment: colorFor([
          'comment',
          'comment.line',
          'comment.block',
        ]) ??
        editor.comment,
    keyword: colorFor([
          'keyword',
          'keyword.control',
          'keyword.operator',
          'storage.type',
        ]) ??
        editor.keyword,
    string: colorFor([
          'string',
          'string.quoted',
          'string.quoted.double',
          'string.quoted.single',
        ]) ??
        editor.string,
    number: colorFor([
          'constant.numeric',
          'constant.numeric.json',
          'number',
        ]) ??
        editor.number,
    function: colorFor([
          'entity.name.function',
          'support.function',
        ]) ??
        editor.function,
    type: colorFor([
          'entity.name.type',
          'support.type',
          'support.type.property-name',
          'support.type.property-name.json',
        ]) ??
        editor.type,
  );
}
