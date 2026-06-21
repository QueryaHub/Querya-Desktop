import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'extension_paths.dart';
import 'models/extension_manifest.dart';

/// Scans the local filesystem for extensions and loads their manifests.
class LocalExtensionRegistry {
  LocalExtensionRegistry._();
  static final LocalExtensionRegistry instance = LocalExtensionRegistry._();

  List<ExtensionManifest> _manifests = [];
  bool _loaded = false;

  /// Returns an unmodifiable list of loaded manifests.
  List<ExtensionManifest> get manifests => List.unmodifiable(_manifests);

  /// Reloads manifests from the disk.
  Future<void> reload() async {
    _loaded = false;
    await load();
  }

  /// Loads manifests from the extensions directory if not already loaded.
  Future<List<ExtensionManifest>> load() async {
    if (_loaded) return manifests;
    
    final dir = await ExtensionPaths.extensionsDirectory();
    final loadedManifests = <ExtensionManifest>[];

    if (await dir.exists()) {
      // Use list() rather than listSync() to prevent blocking the UI
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is Directory) {
          final manifestFile = File(p.join(entity.path, 'manifest.json'));
          if (await manifestFile.exists()) {
            try {
              final content = await manifestFile.readAsString();
              final json = jsonDecode(content) as Map<String, dynamic>;
              final manifest = ExtensionManifest.fromJson(
                json, 
                installPath: entity.path,
              );
              loadedManifests.add(manifest);
            } catch (e) {
              // Log or ignore invalid manifests
              // In the future, we could report these to an error logging service
            }
          }
        }
      }
    }
    
    _manifests = loadedManifests;
    _loaded = true;
    return manifests;
  }
}
