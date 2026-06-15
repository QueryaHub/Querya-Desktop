import '../theme/theme_definition.dart';

/// Marketplace listing model (future `MarketplaceClient` response shape).
///
/// See [docs/market-tech.md](https://github.com/QueryaHub/Querya-Desktop/blob/main/docs/market-tech.md).
class ExtensionManifest {
  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.type,
    required this.version,
    required this.downloadUrl,
    required this.sha256Checksum,
    this.author,
    this.description,
    this.homepage,
    this.license,
    this.preview,
    this.tags = const [],
  });

  static const typeTheme = 'theme';

  final String id;
  final String name;
  final String type;
  final String version;
  final String downloadUrl;
  final String sha256Checksum;
  final String? author;
  final String? description;
  final String? homepage;
  final String? license;
  final String? preview;
  final List<String> tags;

  /// Maps a registry [ThemeDefinition] into marketplace field names.
  ///
  /// [downloadUrl] and [sha256Checksum] are required for remote install (TP-F4);
  /// pass empty strings when building a local-only listing stub.
  factory ExtensionManifest.fromThemeDefinition(
    ThemeDefinition definition, {
    String downloadUrl = '',
    String sha256Checksum = '',
    String type = typeTheme,
  }) {
    final metadata = definition.metadata;
    return ExtensionManifest(
      id: definition.id,
      name: definition.name,
      type: type,
      version: metadata?.version ?? '0.0.0',
      downloadUrl: downloadUrl,
      sha256Checksum: sha256Checksum.isNotEmpty
          ? sha256Checksum
          : (definition.contentHash ?? ''),
      author: metadata?.author,
      description: metadata?.description,
      homepage: metadata?.homepage,
      license: metadata?.license,
      preview: metadata?.preview,
      tags: metadata?.tags ?? const [],
    );
  }
}
