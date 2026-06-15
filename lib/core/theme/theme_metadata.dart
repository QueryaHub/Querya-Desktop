/// Marketplace-oriented metadata carried on [ThemeDefinition].
class ThemeMetadata {
  const ThemeMetadata({
    this.description,
    this.author,
    this.version,
    this.homepage,
    this.license,
    this.preview,
    this.tags = const [],
  });

  final String? description;
  final String? author;
  final String? version;
  final String? homepage;
  final String? license;

  /// Relative asset path or HTTPS URL string (not fetched by the registry).
  final String? preview;
  final List<String> tags;

  bool get hasPickerSubtitle =>
      (author != null && author!.isNotEmpty) || tags.isNotEmpty;

  /// Subtitle for theme picker rows: author, else comma-separated tags.
  String? get pickerSubtitle {
    final authorLabel = author?.trim();
    if (authorLabel != null && authorLabel.isNotEmpty) return authorLabel;
    if (tags.isEmpty) return null;
    return tags.join(', ');
  }

  static ThemeMetadata? fromQueryaJson(Map<String, dynamic> json) {
    final description = _optionalString(json['description']);
    final author = _optionalString(json['author']);
    final version = _optionalString(json['version']);
    final homepage = _optionalString(json['homepage']);
    final license = _optionalString(json['license']);
    final preview = _optionalString(json['preview']);
    final tags = _parseTags(json['tags']);

    if (description == null &&
        author == null &&
        version == null &&
        homepage == null &&
        license == null &&
        preview == null &&
        tags.isEmpty) {
      return null;
    }

    return ThemeMetadata(
      description: description,
      author: author,
      version: version,
      homepage: homepage,
      license: license,
      preview: preview,
      tags: tags,
    );
  }

  static String? _optionalString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _parseTags(Object? raw) {
    if (raw is! List) return const [];

    final tags = <String>[];
    for (final item in raw) {
      if (item is! String) continue;
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) tags.add(trimmed);
    }
    return List.unmodifiable(tags);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeMetadata &&
          description == other.description &&
          author == other.author &&
          version == other.version &&
          homepage == other.homepage &&
          license == other.license &&
          preview == other.preview &&
          _listEquals(tags, other.tags);

  @override
  int get hashCode => Object.hash(
        description,
        author,
        version,
        homepage,
        license,
        preview,
        Object.hashAll(tags),
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
