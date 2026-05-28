import 'dart:convert';

import 'jsonc_preprocessor.dart';

/// Parsed VS Code theme manifest (subset used by Querya).
class VsCodeThemeManifest {
  const VsCodeThemeManifest({
    this.name,
    this.type,
    this.colors = const {},
    this.tokenColors = const [],
  });

  final String? name;

  /// `dark` or `light` when present.
  final String? type;

  final Map<String, String> colors;

  final List<TokenColorRule> tokenColors;

  bool get isDark => type?.toLowerCase() == 'dark';
  bool get isLight => type?.toLowerCase() == 'light';

  factory VsCodeThemeManifest.fromJsonString(String source) {
    final cleaned = stripJsonc(source);
    final dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } on FormatException catch (e) {
      throw VsCodeThemeParseException('Invalid JSON after JSONC strip: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw VsCodeThemeParseException('Theme root must be a JSON object');
    }
    return VsCodeThemeManifest.fromJson(decoded);
  }

  factory VsCodeThemeManifest.fromJson(Map<String, dynamic> json) {
    final colorsRaw = json['colors'];
    final colors = <String, String>{};
    if (colorsRaw is Map) {
      for (final e in colorsRaw.entries) {
        final k = e.key?.toString();
        final v = e.value?.toString();
        if (k != null && k.isNotEmpty && v != null && v.isNotEmpty) {
          colors[k] = v;
        }
      }
    }

    final tokenColorsRaw = json['tokenColors'];
    final rules = <TokenColorRule>[];
    if (tokenColorsRaw is List) {
      for (final item in tokenColorsRaw) {
        if (item is Map<String, dynamic>) {
          final rule = TokenColorRule.tryParse(item);
          if (rule != null) rules.add(rule);
        }
      }
    }

    return VsCodeThemeManifest(
      name: json['name']?.toString(),
      type: json['type']?.toString(),
      colors: colors,
      tokenColors: rules,
    );
  }
}

/// One `tokenColors` entry from a VS Code theme file.
class TokenColorRule {
  const TokenColorRule({
    required this.scopes,
    this.foreground,
    this.background,
    this.fontStyle,
  });

  final List<String> scopes;
  final String? foreground;
  final String? background;
  final String? fontStyle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TokenColorRule &&
          scopes.length == other.scopes.length &&
          _listEquals(scopes, other.scopes) &&
          foreground == other.foreground &&
          background == other.background &&
          fontStyle == other.fontStyle;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(scopes),
        foreground,
        background,
        fontStyle,
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static TokenColorRule? tryParse(Map<String, dynamic> json) {
    final scopeRaw = json['scope'];
    final scopes = <String>[];
    if (scopeRaw is String && scopeRaw.isNotEmpty) {
      scopes.add(scopeRaw);
    } else if (scopeRaw is List) {
      for (final s in scopeRaw) {
        final t = s?.toString();
        if (t != null && t.isNotEmpty) scopes.add(t);
      }
    }
    if (scopes.isEmpty) return null;

    final settings = json['settings'];
    if (settings is! Map) {
      return TokenColorRule(scopes: scopes);
    }

    return TokenColorRule(
      scopes: scopes,
      foreground: settings['foreground']?.toString(),
      background: settings['background']?.toString(),
      fontStyle: settings['fontStyle']?.toString(),
    );
  }
}

class VsCodeThemeParseException implements Exception {
  VsCodeThemeParseException(this.message);
  final String message;

  @override
  String toString() => 'VsCodeThemeParseException: $message';
}
