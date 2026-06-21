import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../storage/app_settings.dart';
import 'builtin_theme_assets.dart';
import 'parser/jsonc_preprocessor.dart';
import 'parser/querya_theme_from_manifest.dart';
import 'parser/querya_theme_from_vscode.dart';
import 'parser/querya_theme_manifest.dart';
import 'parser/vscode_theme_manifest.dart';
import 'querya_theme.dart';
import 'theme_definition.dart';
import 'theme_import_service.dart';
import 'theme_load_result.dart';
import 'theme_metadata.dart';
import 'theme_paths.dart';
import '../extensions/local_extension_registry.dart';
import '../extensions/extension_paths.dart';
import '../extensions/models/extension_manifest.dart';
import '../extensions/models/extension_type.dart';

/// Scans theme directories and exposes lightweight [ThemeDefinition] metadata.
class ThemeRegistryService {
  ThemeRegistryService({
    Future<Directory> Function()? userThemesDirectory,
    Future<Directory> Function()? importedThemesDirectory,
    Future<String> Function(String assetPath)? assetLoader,
    List<String>? bundledThemeAssetFiles,
    int maxCacheEntries = 16,
  })  : _userThemesDirectory =
            userThemesDirectory ?? ThemePaths.userThemesDirectory,
        _importedThemesDirectory =
            importedThemesDirectory ?? ThemePaths.importedThemesDirectory,
        _assetLoader = assetLoader ?? ((path) => rootBundle.loadString(path)),
        _bundledThemeAssetFiles =
            bundledThemeAssetFiles ?? BuiltinThemeAssets.bundledFiles,
        _themeCache = _ThemeLruCache(maxEntries: maxCacheEntries);

  static const defaultMaxCacheEntries = 16;

  final Future<Directory> Function() _userThemesDirectory;
  final Future<Directory> Function() _importedThemesDirectory;
  final Future<String> Function(String assetPath) _assetLoader;
  final List<String> _bundledThemeAssetFiles;
  final _ThemeLruCache _themeCache;
  int _themeParseCount = 0;
  bool _hasMigratedThemes = false;

  /// Number of cache misses that performed a full theme parse.
  @visibleForTesting
  int get themeParseCount => _themeParseCount;

  /// Clears parsed theme cache and parse counter.
  void clearCache() {
    _themeCache.clear();
    _themeParseCount = 0;
  }

  Future<List<ThemeDefinition>> loadThemeDefinitions() async {
    final definitions = <ThemeDefinition>[];

    await _loadBuiltinAssetDefinitions(definitions);

    if (!_hasMigratedThemes) {
      await _migrateLegacyThemesToExtensions();
      _hasMigratedThemes = true;
    }

    await LocalExtensionRegistry.instance.reload();
    for (final manifest in LocalExtensionRegistry.instance.manifests) {
      if (manifest.type != ExtensionType.theme) continue;
      final installPath = manifest.installPath;
      final mainFile = manifest.main;
      if (installPath == null || mainFile == null) continue;

      final file = File(p.join(installPath, mainFile));
      if (!await file.exists()) continue;

      final source = manifest.publisher.toLowerCase() == 'imported'
          ? ThemeSource.imported
          : ThemeSource.filesystem;

      final definition = await _definitionFromFile(file, source, extensionId: manifest.id);
      if (definition != null) {
        definitions.add(definition);
      }
    }

    final legacy = await _legacyImportedDefinition();
    if (legacy != null) {
      definitions.removeWhere(
        (definition) =>
            definition.path == legacy.path &&
            definition.source != ThemeSource.legacyImported,
      );
      definitions.add(legacy);
    }

    definitions.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List.unmodifiable(definitions);
  }

  Future<void> _migrateLegacyThemesToExtensions() async {
    final dirs = [
      (await _userThemesDirectory(), ThemeSource.filesystem),
      (await _importedThemesDirectory(), ThemeSource.imported),
    ];

    final extensionsDir = await ExtensionPaths.ensureExtensionsDirectory();

    for (final pair in dirs) {
      final directory = pair.$1;
      final source = pair.$2;
      if (!await directory.exists()) continue;

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        if (p.basename(entity.path) == ThemeImportService.storedFileName) {
          continue;
        }
        final ext = p.extension(entity.path).toLowerCase();
        if (ext != '.json' && ext != '.jsonc') continue;

        try {
          final definition =
              await _definitionFromFile(entity, source);
          if (definition == null) continue;

          final slug = ThemeImportService.slugifyThemeName(definition.name);
          var finalExtDir = Directory(p.join(extensionsDir.path, slug));
          var counter = 2;
          while (await finalExtDir.exists()) {
            finalExtDir =
                Directory(p.join(extensionsDir.path, '$slug-$counter'));
            counter++;
          }
          await finalExtDir.create(recursive: true);

          final themeFile = File(p.join(finalExtDir.path, 'theme.json'));
          await entity.copy(themeFile.path);

          final manifest = ExtensionManifest(
            id: definition.id,
            name: definition.name,
            version: '1.0.0',
            publisher: source == ThemeSource.imported ? 'Imported' : 'Unknown',
            type: ExtensionType.theme,
            engines: const {'querya_desktop': '*'},
            main: 'theme.json',
            description: 'Migrated custom theme',
          );

          final manifestFile = File(p.join(finalExtDir.path, 'manifest.json'));
          await manifestFile.writeAsString(jsonEncode(manifest.toJson()));

          await entity.delete(); // Delete old file to complete migration
        } catch (_) {}
      }
    }
    // Reload extensions since we might have added new ones
    await LocalExtensionRegistry.instance.reload();
  }

  /// Validates [sourcePath], creates an extension directory, and returns
  /// the scanned [ThemeDefinition].
  Future<ThemeDefinitionImportResult> importThemeFile(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        return const ThemeDefinitionImportFailure('Theme file not found.');
      }

      final raw = await source.readAsString();
      final json = _decodeRoot(raw);
      if (json == null) {
        return const ThemeDefinitionImportFailure('Invalid JSON.');
      }

      final extensionsDir = await ExtensionPaths.ensureExtensionsDirectory();

      final schema = json['schema']?.toString();
      late String logicalId;
      late String preferredBaseName;
      late String contentToWrite;

      if (schema == queryaThemeSchemaV1) {
        final manifest = QueryaThemeManifest.fromJsonString(raw);
        logicalId = manifest.id;
        preferredBaseName = ThemeImportService.safeThemeFileBase(manifest.id);
        contentToWrite = raw;
      } else {
        final manifest = VsCodeThemeManifest.fromJsonString(raw);
        if (manifest.colors.isEmpty) {
          return const ThemeDefinitionImportFailure(
            'Theme file has no "colors" section to import.',
          );
        }
        final displayName = manifest.name?.trim().isNotEmpty == true
            ? manifest.name!.trim()
            : p.basenameWithoutExtension(sourcePath);
        preferredBaseName = ThemeImportService.slugifyThemeName(displayName);
        logicalId = preferredBaseName;
        contentToWrite = raw;
      }

      await LocalExtensionRegistry.instance.load();
      final hash = _contentHash(raw);

      File? sameHashFile;
      ExtensionManifest? sameHashManifest;
      ExtensionManifest? sameIdManifest;

      for (final extManifest in LocalExtensionRegistry.instance.manifests) {
        if (extManifest.type != ExtensionType.theme) continue;
        final installPath = extManifest.installPath;
        final mainFile = extManifest.main;
        if (installPath == null || mainFile == null) continue;

        final file = File(p.join(installPath, mainFile));
        if (await file.exists()) {
          final existingRaw = await file.readAsString();
          if (_contentHash(existingRaw) == hash) {
            sameHashFile = file;
            sameHashManifest = extManifest;
            break;
          }
        }

        if (extManifest.id == logicalId) {
          sameIdManifest = extManifest;
        }
      }

      bool reused = false;
      File resolvedFile;

      if (sameHashManifest != null) {
        reused = true;
        resolvedFile = sameHashFile!;
        logicalId = sameHashManifest.id;
      } else {
        if (sameIdManifest != null) {
          var suffix = 2;
          var candidateId = '$logicalId-$suffix';
          while (LocalExtensionRegistry.instance.manifests.any((m) => m.type == ExtensionType.theme && m.id == candidateId)) {
            suffix++;
            candidateId = '$logicalId-$suffix';
          }
          logicalId = candidateId;
          preferredBaseName = ThemeImportService.safeThemeFileBase(logicalId);
          if (schema == queryaThemeSchemaV1) {
            contentToWrite = _rewriteCustomThemeId(raw, logicalId);
          }
        }

        var finalExtDir =
            Directory(p.join(extensionsDir.path, preferredBaseName));
        var counter = 2;
        while (await finalExtDir.exists()) {
          finalExtDir = Directory(
              p.join(extensionsDir.path, '$preferredBaseName-$counter'));
          counter++;
        }
        await finalExtDir.create(recursive: true);

        resolvedFile = File(p.join(finalExtDir.path, 'theme.json'));
        await resolvedFile.writeAsString(contentToWrite);

        final newManifest = ExtensionManifest(
          id: logicalId,
          name: preferredBaseName,
          version: '1.0.0',
          publisher: 'Unknown',
          type: ExtensionType.theme,
          engines: const {'querya_desktop': '*'},
          main: 'theme.json',
          description: 'Imported custom theme',
        );
        final manifestFile = File(p.join(finalExtDir.path, 'manifest.json'));
        await manifestFile.writeAsString(jsonEncode(newManifest.toJson()));

        await LocalExtensionRegistry.instance.reload();
      }

      final definition = await _definitionFromFile(resolvedFile, ThemeSource.filesystem, extensionId: logicalId);
      if (definition == null) {
        return const ThemeDefinitionImportFailure(
            'Failed to index imported theme.');
      }

      return ThemeDefinitionImportSuccess(
        definition: definition,
        reusedExisting: reused,
      );
    } on QueryaThemeManifestParseException catch (e) {
      return ThemeDefinitionImportFailure(e.message);
    } on VsCodeThemeParseException catch (e) {
      return ThemeDefinitionImportFailure(e.message);
    } on IOException catch (e) {
      return ThemeDefinitionImportFailure(e.toString());
    } on Object catch (e) {
      return ThemeDefinitionImportFailure(e.toString());
    }
  }

  String _rewriteCustomThemeId(String raw, String newId) {
    final decoded = jsonDecode(stripJsonc(raw));
    if (decoded is! Map<String, dynamic>) return raw;
    decoded['id'] = newId;
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  /// Parses a scanned [definition] into a runtime [QueryaTheme].
  Future<ThemeLoadResult> loadTheme(ThemeDefinition definition) async {
    final path = definition.path;
    if (path == null || path.isEmpty) {
      return ThemeLoadFailure(
        definition: definition,
        message: 'Theme file path is missing.',
      );
    }

    final cacheKey = definition.stableCacheKey;
    final cachedTheme = _themeCache.get(cacheKey);
    if (cachedTheme != null) {
      return ThemeLoadSuccess(definition: definition, theme: cachedTheme);
    }

    try {
      final raw = await _readThemeRaw(definition);
      if (raw == null) {
        return ThemeLoadFailure(
          definition: definition,
          message: 'Theme file not found.',
        );
      }

      final theme = switch (definition.format) {
        ThemeFormat.queryaCustom => _loadCustomTheme(raw),
        ThemeFormat.vscode => _loadVsCodeTheme(raw),
      };
      _themeCache.put(cacheKey, theme);
      _themeParseCount++;
      return ThemeLoadSuccess(definition: definition, theme: theme);
    } on QueryaThemeManifestParseException catch (e) {
      return ThemeLoadFailure(
        definition: definition,
        message: e.message,
        error: e,
      );
    } on VsCodeThemeParseException catch (e) {
      return ThemeLoadFailure(
        definition: definition,
        message: e.message,
        error: e,
      );
    } on IOException catch (e) {
      return ThemeLoadFailure(
        definition: definition,
        message: 'Failed to read theme file.',
        error: e,
      );
    } on Object catch (e) {
      return ThemeLoadFailure(
        definition: definition,
        message: 'Failed to load theme.',
        error: e,
      );
    }
  }

  QueryaTheme _loadCustomTheme(String raw) {
    final manifest = QueryaThemeManifest.fromJsonString(raw);
    return queryaThemeFromManifest(manifest);
  }

  QueryaTheme _loadVsCodeTheme(String raw) {
    final manifest = VsCodeThemeManifest.fromJsonString(raw);
    if (manifest.colors.isEmpty) {
      throw VsCodeThemeParseException(
        'Theme file has no "colors" section to import.',
      );
    }
    return buildQueryaThemeFromVsCodeManifest(manifest);
  }

  Future<ThemeDefinition?> _legacyImportedDefinition() async {
    try {
      final settings = AppSettings.instance;
      final importedColors = await settings.getThemeImportedColors();
      final importName = await settings.getThemeImportName();
      final importPath = await settings.getThemeImportPath();
      final storedFile = await ThemeImportService.persistedImportFile();
      final hasStoredFile = await storedFile.exists();

      final hasLegacyData = importedColors.isNotEmpty ||
          (importName != null && importName.isNotEmpty) ||
          (importPath != null && importPath.isNotEmpty) ||
          hasStoredFile;
      if (!hasLegacyData) return null;

      final path = _firstNonEmpty([
        importPath,
        if (hasStoredFile) storedFile.path,
        storedFile.path,
      ]);
      if (path == null) return null;

      final name = (importName != null && importName.isNotEmpty)
          ? importName
          : 'Imported theme';

      var isDark = true;
      DateTime? lastModified;
      String? contentHash;

      final file = File(path);
      if (await file.exists()) {
        try {
          final stat = await file.stat();
          lastModified = stat.modified;
          final raw = await file.readAsString();
          contentHash = _contentHash(raw);
          final manifest = VsCodeThemeManifest.fromJsonString(raw);
          isDark = manifest.isDark || !manifest.isLight;
        } on Object catch (e) {
          _logScanError(path, e);
        }
      }

      return ThemeDefinition(
        id: ThemeImportService.legacyImportedThemeId,
        name: name,
        source: ThemeSource.legacyImported,
        format: ThemeFormat.vscode,
        isDark: isDark,
        path: path,
        lastModified: lastModified,
        contentHash: contentHash,
      );
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('ThemeRegistryService: legacy import skipped ($e)');
      }
      return null;
    }
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> _loadBuiltinAssetDefinitions(List<ThemeDefinition> out) async {
    for (final fileName in _bundledThemeAssetFiles) {
      final assetPath = BuiltinThemeAssets.assetPath(fileName);
      try {
        final raw = await _readAssetString(assetPath);
        final hash = _contentHash(raw);
        final json = _decodeRoot(raw);
        if (json == null) {
          _logScanError(assetPath, 'Invalid JSON');
          continue;
        }

        final definition = _definitionFromRaw(
          json: json,
          path: assetPath,
          fileBaseName: p.basenameWithoutExtension(fileName),
          source: ThemeSource.builtin,
          contentHash: hash,
        );
        if (definition != null) {
          out.add(definition);
        }
      } on Object catch (e) {
        _logScanError(assetPath, e);
      }
    }
  }

  Future<String?> _readThemeRaw(ThemeDefinition definition) async {
    final path = definition.path;
    if (path == null || path.isEmpty) return null;

    if (definition.source == ThemeSource.builtin && _isAssetPath(path)) {
      try {
        return await _readAssetString(path);
      } on Object {
        return null;
      }
    }

    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<String> _readAssetString(String assetPath) => _assetLoader(assetPath);

  static bool _isAssetPath(String path) => path.startsWith('assets/');

  Future<ThemeDefinition?> _definitionFromFile(
    File file,
    ThemeSource source, {
    String? extensionId,
  }) async {
    try {
      final stat = await file.stat();
      final raw = await file.readAsString();
      final hash = _contentHash(raw);
      final json = _decodeRoot(raw);
      if (json == null) {
        _logScanError(file.path, 'Invalid JSON');
        return null;
      }

      final schema = json['schema']?.toString();
      if (schema == queryaThemeSchemaV1) {
        return _definitionFromRaw(
          json: json,
          path: file.path,
          fileBaseName: p.basenameWithoutExtension(file.path),
          source: source,
          contentHash: hash,
          lastModified: stat.modified,
          extensionId: extensionId,
        );
      }

      return _definitionFromRaw(
        json: json,
        path: file.path,
        fileBaseName: p.basenameWithoutExtension(file.path),
        source: source,
        contentHash: hash,
        lastModified: stat.modified,
        extensionId: extensionId,
      );
    } on Object catch (e) {
      _logScanError(file.path, e);
      return null;
    }
  }

  ThemeDefinition? _definitionFromRaw({
    required Map<String, dynamic> json,
    required String path,
    required String fileBaseName,
    required ThemeSource source,
    required String contentHash,
    DateTime? lastModified,
    String? extensionId,
  }) {
    final schema = json['schema']?.toString();
    if (schema == queryaThemeSchemaV1) {
      return _customDefinition(
        json: json,
        source: source,
        contentHash: contentHash,
        path: path,
        lastModified: lastModified,
        extensionId: extensionId,
      );
    }

    return _vscodeDefinition(
      json: json,
      source: source,
      contentHash: contentHash,
      fileBaseName: fileBaseName,
      path: path,
      lastModified: lastModified,
      extensionId: extensionId,
    );
  }

  ThemeDefinition? _customDefinition({
    required Map<String, dynamic> json,
    required ThemeSource source,
    required String contentHash,
    required String path,
    DateTime? lastModified,
    String? extensionId,
  }) {
    final id = extensionId ?? json['id']?.toString().trim();
    final name = json['name']?.toString().trim();
    final type = json['type']?.toString().trim().toLowerCase();

    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      _logScanError(path, 'Missing required custom theme fields');
      return null;
    }
    if (type != 'dark' && type != 'light') {
      _logScanError(path, 'Invalid custom theme type "$type"');
      return null;
    }

    return ThemeDefinition(
      id: id,
      name: name,
      source: source,
      format: ThemeFormat.queryaCustom,
      isDark: type == 'dark',
      path: path,
      lastModified: lastModified,
      contentHash: contentHash,
      metadata: ThemeMetadata.fromQueryaJson(json),
    );
  }

  ThemeDefinition? _vscodeDefinition({
    required Map<String, dynamic> json,
    required ThemeSource source,
    required String contentHash,
    required String fileBaseName,
    required String path,
    DateTime? lastModified,
    String? extensionId,
  }) {
    final rawName = json['name']?.toString().trim();
    final name = rawName != null && rawName.isNotEmpty ? rawName : fileBaseName;
    final type = json['type']?.toString().trim().toLowerCase();

    return ThemeDefinition(
      id: extensionId ?? fileBaseName,
      name: name,
      source: source,
      format: ThemeFormat.vscode,
      isDark: type == 'dark',
      path: path,
      lastModified: lastModified,
      contentHash: contentHash,
    );
  }

  Map<String, dynamic>? _decodeRoot(String raw) {
    try {
      final decoded = jsonDecode(stripJsonc(raw));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      return null;
    }
    return null;
  }

  static String _contentHash(String content) {
    final bytes = utf8.encode(content);
    var hash = 0x811c9dc5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  void _logScanError(String path, Object error) {
    if (kDebugMode) {
      debugPrint('ThemeRegistryService: skipped $path ($error)');
    }
  }
}

class _ThemeLruCache {
  _ThemeLruCache({required this.maxEntries});

  final int maxEntries;
  final _entries = <String, QueryaTheme>{};

  QueryaTheme? get(String key) {
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  void put(String key, QueryaTheme theme) {
    _entries.remove(key);
    _entries[key] = theme;
    while (_entries.length > maxEntries) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
    }
  }

  void clear() => _entries.clear();
}
