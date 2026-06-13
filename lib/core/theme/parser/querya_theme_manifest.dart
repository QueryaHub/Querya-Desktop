import 'dart:convert';

import 'jsonc_preprocessor.dart';
import 'vscode_theme_manifest.dart';

const queryaThemeSchemaV1 = 'querya.theme.v1';

enum QueryaThemeType {
  dark,
  light,
}

/// Parsed Querya custom theme manifest (`querya.theme.v1`).
class QueryaThemeManifest {
  const QueryaThemeManifest({
    required this.schema,
    required this.id,
    required this.name,
    required this.type,
    required this.shadcnColors,
    required this.editorColors,
    this.tokenColors = const [],
    this.description,
    this.author,
    this.version,
  });

  final String schema;
  final String id;
  final String name;
  final QueryaThemeType type;
  final Map<String, String> shadcnColors;
  final Map<String, String> editorColors;
  final List<TokenColorRule> tokenColors;
  final String? description;
  final String? author;
  final String? version;

  bool get isDark => type == QueryaThemeType.dark;
  bool get isLight => type == QueryaThemeType.light;

  factory QueryaThemeManifest.fromJsonString(String source) {
    final cleaned = stripJsonc(source);
    final dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } on FormatException catch (e) {
      throw QueryaThemeManifestParseException(
        'Invalid JSON after JSONC strip: ${e.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw QueryaThemeManifestParseException('Theme root must be a JSON object');
    }
    return QueryaThemeManifest.fromJson(decoded);
  }

  factory QueryaThemeManifest.fromJson(Map<String, dynamic> json) {
    final schema = _requiredString(json, 'schema');
    if (schema != queryaThemeSchemaV1) {
      throw QueryaThemeManifestParseException(
        'Unsupported schema "$schema"; expected "$queryaThemeSchemaV1"',
      );
    }

    final id = _requiredString(json, 'id');
    final name = _requiredString(json, 'name');
    final type = _parseType(_requiredString(json, 'type'));
    final shadcnColors = _parseColorMap(json['shadcn_colors'], 'shadcn_colors');
    final editorColors = _parseColorMap(json['editor_colors'], 'editor_colors');

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

    return QueryaThemeManifest(
      schema: schema,
      id: id,
      name: name,
      type: type,
      shadcnColors: shadcnColors,
      editorColors: editorColors,
      tokenColors: List.unmodifiable(rules),
      description: _optionalString(json['description']),
      author: _optionalString(json['author']),
      version: _optionalString(json['version']),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key)) {
      throw QueryaThemeManifestParseException('Missing required field "$key"');
    }
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw QueryaThemeManifestParseException('Invalid or empty "$key"');
    }
    return value.trim();
  }

  static String? _optionalString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static QueryaThemeType _parseType(String raw) {
    switch (raw.toLowerCase()) {
      case 'dark':
        return QueryaThemeType.dark;
      case 'light':
        return QueryaThemeType.light;
      default:
        throw QueryaThemeManifestParseException('Invalid type "$raw"; expected dark or light');
    }
  }

  static Map<String, String> _parseColorMap(Object? raw, String fieldName) {
    if (raw == null) {
      throw QueryaThemeManifestParseException('Missing required field "$fieldName"');
    }
    if (raw is! Map) {
      throw QueryaThemeManifestParseException('"$fieldName" must be a JSON object');
    }

    final colors = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString();
      final value = entry.value?.toString();
      if (key != null && key.isNotEmpty && value != null && value.isNotEmpty) {
        colors[key] = value;
      }
    }
    return Map.unmodifiable(colors);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryaThemeManifest &&
          schema == other.schema &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          _mapEquals(shadcnColors, other.shadcnColors) &&
          _mapEquals(editorColors, other.editorColors) &&
          _listEquals(tokenColors, other.tokenColors) &&
          description == other.description &&
          author == other.author &&
          version == other.version;

  @override
  int get hashCode => Object.hash(
        schema,
        id,
        name,
        type,
        Object.hashAll(shadcnColors.entries),
        Object.hashAll(editorColors.entries),
        Object.hashAll(tokenColors),
        description,
        author,
        version,
      );

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _listEquals(List<TokenColorRule> a, List<TokenColorRule> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class QueryaThemeManifestParseException implements Exception {
  const QueryaThemeManifestParseException(this.message);
  final String message;

  @override
  String toString() => 'QueryaThemeManifestParseException: $message';
}
