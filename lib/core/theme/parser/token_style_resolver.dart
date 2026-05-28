import 'package:flutter/material.dart';

import 'color_parser.dart';
import 'vscode_theme_manifest.dart';

/// Resolves TextMate scopes to [TextStyle] using VS Code `tokenColors` rules.
///
/// Walks scope prefixes from most specific to least (`a.b.c` → `a.b` → `a`).
class TokenStyleResolver {
  TokenStyleResolver({
    required List<TokenColorRule> rules,
    required TextStyle defaultStyle,
  })  : _rules = rules,
        _defaultStyle = defaultStyle;

  final List<TokenColorRule> _rules;
  final TextStyle _defaultStyle;
  final Map<String, TextStyle> _cache = {};

  /// Longest-prefix match for [scope] with per-scope cache.
  TextStyle resolve(String scope) =>
      _cache.putIfAbsent(scope, () => _resolveUncached(scope));

  TextStyle _resolveUncached(String scope) {
    for (final prefix in _scopePrefixes(scope)) {
      for (final rule in _rules) {
        if (rule.scopes.contains(prefix)) {
          return _styleFromRule(rule);
        }
      }
    }
    return _defaultStyle;
  }

  List<String> _scopePrefixes(String scope) {
    final parts = scope.split('.');
    return [
      for (var i = parts.length; i >= 1; i--)
        parts.sublist(0, i).join('.'),
    ];
  }

  TextStyle _styleFromRule(TokenColorRule rule) {
    Color? color;
    if (rule.foreground != null) {
      try {
        color = parseVsCodeColor(rule.foreground!);
      } on FormatException {
        color = null;
      }
    }

    FontStyle? fontStyle;
    FontWeight? fontWeight;
    TextDecoration? decoration;
    final fs = rule.fontStyle?.toLowerCase();
    if (fs != null) {
      if (fs.contains('italic')) fontStyle = FontStyle.italic;
      if (fs.contains('bold')) fontWeight = FontWeight.bold;
      if (fs.contains('underline')) decoration = TextDecoration.underline;
    }

    return _defaultStyle.copyWith(
      color: color ?? _defaultStyle.color,
      fontStyle: fontStyle ?? _defaultStyle.fontStyle,
      fontWeight: fontWeight ?? _defaultStyle.fontWeight,
      decoration: decoration ?? _defaultStyle.decoration,
    );
  }
}
