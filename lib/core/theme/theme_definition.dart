enum ThemeSource {
  builtin,
  imported,
  filesystem,
  legacyImported,
}

enum ThemeFormat {
  queryaCustom,
  vscode,
}

/// Lightweight theme metadata for registry lists and load results.
class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.name,
    required this.source,
    required this.format,
    required this.isDark,
    this.path,
    this.lastModified,
    this.contentHash,
  });

  final String id;
  final String name;
  final ThemeSource source;
  final ThemeFormat format;
  final bool isDark;
  final String? path;
  final DateTime? lastModified;
  final String? contentHash;

  bool get isFileBacked =>
      source == ThemeSource.filesystem ||
      source == ThemeSource.imported ||
      source == ThemeSource.legacyImported;

  String get stableCacheKey =>
      '${source.name}:$id:${contentHash ?? path ?? name}';
}
