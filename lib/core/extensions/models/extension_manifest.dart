import 'dart:io';

import 'package:path/path.dart' as p;

import '../../theme/theme_definition.dart';
import 'extension_contributions.dart';
import 'extension_type.dart';
import 'sandbox_capabilities.dart';

class ExtensionManifest {
  static const typeTheme = ExtensionType.theme;

  final String id;
  final String name;
  final String version;
  final String publisher;
  final ExtensionType type;
  final Map<String, String> engines;
  final String? main;
  final String? icon;
  final String? description;
  final String? installPath;
  final String? downloadUrl;
  final String? sha256Checksum;
  final String? author;
  final String? homepage;
  final String? license;
  final String? preview;
  final List<String> tags;

  /// Sandbox requirements declared by the extension (Block E). Null when the
  /// manifest has no `sandbox` block (e.g. plain themes).
  final SandboxCapabilities? sandbox;

  /// Capability flags from `capabilities` in manifest.json.
  final ExtensionCapabilities? capabilities;

  /// Extension points from `contributions` in manifest.json.
  final ExtensionContributions? contributions;

  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.publisher,
    required this.type,
    required this.engines,
    this.main,
    this.icon,
    this.description,
    this.installPath,
    this.downloadUrl,
    this.sha256Checksum,
    this.author,
    this.homepage,
    this.license,
    this.preview,
    this.tags = const [],
    this.sandbox,
    this.capabilities,
    this.contributions,
  });

  /// Drivers contributed by this package (empty when none).
  Iterable<DriverContribution> get contributedDrivers =>
      contributions?.drivers ?? const [];

  /// Absolute path to the packaged icon, or null when missing on disk.
  String? get resolvedIconPath {
    final rel = icon?.trim();
    final root = installPath;
    if (rel == null || rel.isEmpty || root == null || root.isEmpty) {
      return null;
    }
    final path = p.join(root, rel);
    return File(path).existsSync() ? path : null;
  }

  /// Maps a registry [ThemeDefinition] into marketplace field names.
  factory ExtensionManifest.fromThemeDefinition(
    ThemeDefinition definition, {
    String downloadUrl = '',
    String sha256Checksum = '',
    ExtensionType type = typeTheme,
  }) {
    final metadata = definition.metadata;
    return ExtensionManifest(
      id: definition.id,
      name: definition.name,
      publisher: metadata?.author ?? 'Unknown',
      type: type,
      version: metadata?.version ?? '0.0.0',
      engines: const {'querya_desktop': '^0.4.7'},
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

  factory ExtensionManifest.fromJson(Map<String, dynamic> json,
      {String? installPath}) {
    return ExtensionManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String? ?? '0.0.0',
      publisher: json['publisher'] as String? ??
          json['author'] as String? ??
          'Unknown',
      type: ExtensionType.fromString(json['type'] as String? ?? ''),
      engines: Map<String, String>.from(json['engines'] as Map? ?? {}),
      main: json['main'] as String?,
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      installPath: installPath,
      downloadUrl: json['downloadUrl'] as String?,
      sha256Checksum:
          json['sha256Checksum'] as String? ?? json['sha256'] as String?,
      author: json['author'] as String?,
      homepage: json['homepage'] as String?,
      license: json['license'] as String?,
      preview: json['preview'] as String?,
      tags: List<String>.from(json['tags'] as List? ?? []),
      sandbox: json['sandbox'] is Map<String, dynamic>
          ? SandboxCapabilities.fromJson(
              json['sandbox'] as Map<String, dynamic>)
          : (json['sandbox'] is Map
              ? SandboxCapabilities.fromJson(
                  Map<String, dynamic>.from(json['sandbox'] as Map))
              : null),
      capabilities: _parseCapabilities(json['capabilities']),
      contributions: _parseContributions(json['contributions']),
    );
  }

  static ExtensionCapabilities? _parseCapabilities(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return ExtensionCapabilities.fromJson(raw);
    }
    if (raw is Map) {
      return ExtensionCapabilities.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  static ExtensionContributions? _parseContributions(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return ExtensionContributions.fromJson(raw);
    }
    if (raw is Map) {
      return ExtensionContributions.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'publisher': publisher,
      'type': type.value,
      'engines': engines,
      if (main != null) 'main': main,
      if (icon != null) 'icon': icon,
      if (description != null) 'description': description,
      if (downloadUrl != null) 'downloadUrl': downloadUrl,
      if (sha256Checksum != null) 'sha256Checksum': sha256Checksum,
      if (author != null) 'author': author,
      if (homepage != null) 'homepage': homepage,
      if (license != null) 'license': license,
      if (preview != null) 'preview': preview,
      if (tags.isNotEmpty) 'tags': tags,
      if (sandbox != null) 'sandbox': sandbox!.toJson(),
      if (capabilities != null && !capabilities!.isEmpty)
        'capabilities': capabilities!.toJson(),
      if (contributions != null && !contributions!.isEmpty)
        'contributions': contributions!.toJson(),
    };
  }
}
