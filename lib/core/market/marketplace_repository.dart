import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';

/// Abstract repository contract for Marketplace operations (Block B).
///
/// See [docs/market-tech.md] and Block B specification.
abstract class MarketplaceRepository {
  static MarketplaceRepository instance = MockMarketplaceRepository();

  /// Returns trending and recommended marketplace extensions.
  Future<List<ExtensionManifest>> getTrending({ExtensionType? type});

  /// Searches the marketplace catalog by query string and optional type filter.
  Future<List<ExtensionManifest>> search(String query, {ExtensionType? type});

  /// Simulates downloading an archive from [url] with progress reporting.
  Future<File> download(String url, {void Function(double)? onProgress});

  /// Installs an extension by downloading, validating, and registering it locally.
  Future<void> install(
    ExtensionManifest manifest, {
    void Function(double)? onProgress,
  });

  /// Uninstalls a locally installed extension by ID.
  Future<void> uninstall(String extensionId);
}

/// In-memory mock implementation for local UI development and testing (Release 0.4.8).
class MockMarketplaceRepository implements MarketplaceRepository {
  MockMarketplaceRepository({List<ExtensionManifest>? seed})
      : _items = List<ExtensionManifest>.from(seed ?? _defaultMocks);

  final List<ExtensionManifest> _items;

  static final List<ExtensionManifest> _defaultMocks = [
    const ExtensionManifest(
      id: 'queryahub.clickhouse-driver',
      name: 'ClickHouse Driver',
      version: '1.0.0',
      publisher: 'QueryaHub',
      type: ExtensionType.databaseDriver,
      engines: {'querya_desktop': '^0.4.7'},
      description: 'Full support for ClickHouse databases including Dictionaries, Materialized Views, and real-time query metrics.',
      downloadUrl: 'https://cdn.queryahub.com/extensions/clickhouse-driver-1.0.0.zip',
      sha256Checksum: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      homepage: 'https://queryahub.com/drivers/clickhouse',
      license: 'MIT',
      tags: ['database', 'clickhouse', 'olap', 'official'],
    ),
    const ExtensionManifest(
      id: 'community.redis-driver',
      name: 'Redis Driver',
      version: '0.9.5',
      publisher: 'Community',
      type: ExtensionType.databaseDriver,
      engines: {'querya_desktop': '^0.4.7'},
      description: 'Connect to Redis instances, visualize key-value storage, inspect Pub/Sub channels, and edit JSON documents.',
      downloadUrl: 'https://cdn.queryahub.com/extensions/redis-driver-0.9.5.zip',
      sha256Checksum: '8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4',
      homepage: 'https://github.com/queryahub/redis-driver',
      license: 'Apache-2.0',
      tags: ['database', 'redis', 'nosql', 'key-value'],
    ),
    const ExtensionManifest(
      id: 'queryahub.cyberpunk-neon',
      name: 'Cyberpunk Neon',
      version: '1.2.0',
      publisher: 'QueryaHub',
      type: ExtensionType.theme,
      engines: {'querya_desktop': '^0.4.7'},
      description: 'Vibrant neon color scheme inspired by Cyberpunk 2077 with glowing syntax highlighting and dark futuristic workbench.',
      downloadUrl: 'https://cdn.queryahub.com/themes/cyberpunk-neon-1.2.0.zip',
      sha256Checksum: 'a1b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef0',
      homepage: 'https://queryahub.com/themes/cyberpunk',
      license: 'MIT',
      tags: ['theme', 'dark', 'cyberpunk', 'neon', 'official'],
    ),
    const ExtensionManifest(
      id: 'community.nord-theme',
      name: 'Nord Theme',
      version: '0.8.2',
      publisher: 'Community',
      type: ExtensionType.theme,
      engines: {'querya_desktop': '^0.4.7'},
      description: 'An arctic, north-bluish clean and elegant color palette designed for focused, distraction-free SQL coding.',
      downloadUrl: 'https://cdn.queryahub.com/themes/nord-theme-0.8.2.zip',
      sha256Checksum: 'b2c3d4e5f6a10718293a4b5c6d7e8f90123456789abcdef0123456789abcdef1',
      homepage: 'https://github.com/arcticicestudio/nord',
      license: 'MIT',
      tags: ['theme', 'dark', 'nord', 'arctic', 'minimal'],
    ),
    const ExtensionManifest(
      id: 'queryahub.mongodb-driver',
      name: 'MongoDB Driver',
      version: '1.1.0',
      publisher: 'QueryaHub',
      type: ExtensionType.databaseDriver,
      engines: {'querya_desktop': '^0.4.7'},
      description: 'Explore MongoDB collections, execute aggregation pipelines, and view BSON documents in an interactive tree view.',
      downloadUrl: 'https://cdn.queryahub.com/extensions/mongodb-driver-1.1.0.zip',
      sha256Checksum: 'c3d4e5f6a1b20718293a4b5c6d7e8f90123456789abcdef0123456789abcdef2',
      homepage: 'https://queryahub.com/drivers/mongodb',
      license: 'MIT',
      tags: ['database', 'mongodb', 'nosql', 'bson', 'official'],
    ),
    const ExtensionManifest(
      id: 'community.postgres-exporter',
      name: 'PostgreSQL Schema Exporter',
      version: '0.5.0',
      publisher: 'Community',
      type: ExtensionType.databaseDriver,
      engines: {'querya_desktop': '^0.4.7'},
      description: 'Export complex PostgreSQL schemas to dbdiagram.io, Mermaid ERD, and DDL scripts with one click.',
      downloadUrl: 'https://cdn.queryahub.com/extensions/postgres-exporter-0.5.0.zip',
      sha256Checksum: 'd4e5f6a1b2c30718293a4b5c6d7e8f90123456789abcdef0123456789abcdef3',
      homepage: 'https://github.com/querya-community/postgres-exporter',
      license: 'MIT',
      tags: ['postgresql', 'schema', 'export', 'erd', 'mermaid'],
    ),
  ];

  @override
  Future<List<ExtensionManifest>> getTrending({ExtensionType? type}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _items.where((item) {
      if (type != null && item.type != type) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Future<List<ExtensionManifest>> search(String query, {ExtensionType? type}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final normalized = query.trim().toLowerCase();
    return _items.where((item) {
      if (type != null && item.type != type) return false;
      if (normalized.isEmpty) return true;
      return item.name.toLowerCase().contains(normalized) ||
          item.id.toLowerCase().contains(normalized) ||
          item.publisher.toLowerCase().contains(normalized) ||
          (item.description?.toLowerCase().contains(normalized) ?? false) ||
          item.tags.any((tag) => tag.toLowerCase().contains(normalized));
    }).toList(growable: false);
  }

  @override
  Future<File> download(String url, {void Function(double)? onProgress}) async {
    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      onProgress?.call(i / 10.0);
    }
    final tmpDir = Directory.systemTemp;
    final file = File(p.join(tmpDir.path, 'querya_ext_mock_${DateTime.now().millisecondsSinceEpoch}.zip'));
    await file.writeAsString('mock archive payload');
    return file;
  }

  @override
  Future<void> install(
    ExtensionManifest manifest, {
    void Function(double)? onProgress,
  }) async {
    // Simulate download & verification progress
    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      onProgress?.call(i / 10.0);
    }

    // Persist to local extensions directory so LocalExtensionRegistry discovers it
    final dir = await ExtensionPaths.extensionsDirectory();
    final extDir = Directory(p.join(dir.path, manifest.id));
    if (!await extDir.exists()) {
      await extDir.create(recursive: true);
    }

    final manifestFile = File(p.join(extDir.path, 'manifest.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await manifestFile.writeAsString(encoder.convert(manifest.toJson()));

    // Reload local registry
    await LocalExtensionRegistry.instance.reload();
  }

  @override
  Future<void> uninstall(String extensionId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    
    // Check local extension registry first
    final manifest = LocalExtensionRegistry.instance.manifests
        .where((e) => e.id == extensionId)
        .firstOrNull;

    if (manifest != null && manifest.installPath != null) {
      final extDir = Directory(manifest.installPath!);
      if (await extDir.exists()) {
        await extDir.delete(recursive: true);
      }
    } else {
      // Fallback: check standard extensions directory by ID
      final dir = await ExtensionPaths.extensionsDirectory();
      final extDir = Directory(p.join(dir.path, extensionId));
      if (await extDir.exists()) {
        await extDir.delete(recursive: true);
      }
    }

    await LocalExtensionRegistry.instance.reload();
  }
}
