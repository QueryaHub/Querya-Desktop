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

    await _scanDirectory(
      await _userThemesDirectory(),
      ThemeSource.filesystem,
      definitions,
    );
    await _scanDirectory(
      await _importedThemesDirectory(),
      ThemeSource.imported,
      definitions,
    );

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

  /// Validates [sourcePath], copies into the user themes directory, and returns
  /// the scanned [ThemeDefinition].
  Future<ThemeDefinitionImportResult> importThemeFile(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        return const ThemeDefinitionImportFailure('Theme file not found.');
      }

      final raw = await source.readAsString();
      final hash = _contentHash(raw);
      final json = _decodeRoot(raw);
      if (json == null) {
        return const ThemeDefinitionImportFailure('Invalid JSON.');
      }

      final themesDir = await _userThemesDirectory();
      if (!await themesDir.exists()) {
        await themesDir.create(recursive: true);
      }

      final schema = json['schema']?.toString();
      late final String logicalId;
      late final String preferredBaseName;
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

      var resolved = await _resolveImportDestination(
        themesDir: themesDir,
        hash: hash,
        logicalId: logicalId,
        preferredBaseName: preferredBaseName,
      );

      if (!resolved.reused &&
          schema == queryaThemeSchemaV1 &&
          resolved.renamedId != null) {
        contentToWrite = _rewriteCustomThemeId(raw, resolved.renamedId!);
      }

      if (!resolved.reused) {
        await resolved.file.writeAsString(contentToWrite);
      }

      final definition =
          await _definitionFromFile(resolved.file, ThemeSource.filesystem);
      if (definition == null) {
        return const ThemeDefinitionImportFailure(
          'Failed to index imported theme.',
        );
      }

      return ThemeDefinitionImportSuccess(
        definition: definition,
        reusedExisting: resolved.reused,
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

  Future<void> _scanDirectory(
    Directory directory,
    ThemeSource source,
    List<ThemeDefinition> out,
  ) async {
    if (!await directory.exists()) return;

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        if (p.basename(entity.path) == 'imported') continue;
        continue;
      }
      if (entity is! File) continue;

      if (p.basename(entity.path) == ThemeImportService.storedFileName) {
        continue;
      }

      final ext = p.extension(entity.path).toLowerCase();
      if (ext != '.json' && ext != '.jsonc') continue;

      final definition = await _definitionFromFile(entity, source);
      if (definition != null) {
        out.add(definition);
      }
    }
  }

  Future<ThemeDefinition?> _definitionFromFile(
    File file,
    ThemeSource source,
  ) async {
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
        );
      }

      return _definitionFromRaw(
        json: json,
        path: file.path,
        fileBaseName: p.basenameWithoutExtension(file.path),
        source: source,
        contentHash: hash,
        lastModified: stat.modified,
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
  }) {
    final schema = json['schema']?.toString();
    if (schema == queryaThemeSchemaV1) {
      return _customDefinition(
        json: json,
        source: source,
        contentHash: contentHash,
        path: path,
        lastModified: lastModified,
      );
    }

    return _vscodeDefinition(
      json: json,
      source: source,
      contentHash: contentHash,
      fileBaseName: fileBaseName,
      path: path,
      lastModified: lastModified,
    );
  }

  ThemeDefinition? _customDefinition({
    required Map<String, dynamic> json,
    required ThemeSource source,
    required String contentHash,
    required String path,
    DateTime? lastModified,
  }) {
    final id = json['id']?.toString().trim();
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
  }) {
    final rawName = json['name']?.toString().trim();
    final name = rawName != null && rawName.isNotEmpty ? rawName : fileBaseName;
    final type = json['type']?.toString().trim().toLowerCase();

    return ThemeDefinition(
      id: fileBaseName,
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

  Future<_ResolvedImportDestination> _resolveImportDestination({
    required Directory themesDir,
    required String hash,
    required String logicalId,
    required String preferredBaseName,
  }) async {
    File? sameIdFile;

    await for (final entity in themesDir.list(followLinks: false)) {
      if (entity is Directory) continue;
      if (entity is! File) continue;

      final name = p.basename(entity.path);
      if (name == ThemeImportService.storedFileName) continue;

      final ext = p.extension(entity.path).toLowerCase();
      if (ext != '.json' && ext != '.jsonc') continue;

      late final String existingRaw;
      try {
        existingRaw = await entity.readAsString();
      } on IOException {
        continue;
      }

      if (_contentHash(existingRaw) == hash) {
        return _ResolvedImportDestination(file: entity, reused: true);
      }

      final definition =
          await _definitionFromFile(entity, ThemeSource.filesystem);
      if (definition?.id == logicalId) {
        sameIdFile = entity;
      }
    }

    if (sameIdFile != null) {
      final renamedId = await _nextRenamedThemeId(themesDir, logicalId);
      final baseName = ThemeImportService.safeThemeFileBase(renamedId);
      final primary = File(p.join(themesDir.path, '$baseName.json'));
      final file = await primary.exists()
          ? await _nextAvailableThemeFile(themesDir, baseName, startSuffix: 2)
          : primary;
      return _ResolvedImportDestination(
        file: file,
        reused: false,
        renamedId: renamedId,
      );
    }

    final primary = File(p.join(themesDir.path, '$preferredBaseName.json'));
    if (!await primary.exists()) {
      return _ResolvedImportDestination(file: primary, reused: false);
    }

    final file = await _nextAvailableThemeFile(
      themesDir,
      preferredBaseName,
      startSuffix: 2,
    );
    return _ResolvedImportDestination(file: file, reused: false);
  }

  Future<String> _nextRenamedThemeId(Directory themesDir, String baseId) async {
    for (var suffix = 2; suffix < 1000; suffix++) {
      final candidate = '$baseId-$suffix';
      final taken = await _themeIdExists(themesDir, candidate);
      if (!taken) return candidate;
    }
    return '$baseId-${_contentHash(baseId)}';
  }

  Future<bool> _themeIdExists(Directory themesDir, String id) async {
    await for (final entity in themesDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (ext != '.json' && ext != '.jsonc') continue;
      final definition =
          await _definitionFromFile(entity, ThemeSource.filesystem);
      if (definition?.id == id) return true;
    }
    return false;
  }

  Future<File> _nextAvailableThemeFile(
    Directory themesDir,
    String baseName, {
    int startSuffix = 2,
  }) async {
    for (var suffix = startSuffix; suffix < 1000; suffix++) {
      final candidate = File(p.join(themesDir.path, '$baseName-$suffix.json'));
      if (!await candidate.exists()) return candidate;
    }
    return File(
      p.join(themesDir.path,
          '$baseName-${DateTime.now().millisecondsSinceEpoch}.json'),
    );
  }

  String _rewriteCustomThemeId(String raw, String newId) {
    final decoded = jsonDecode(stripJsonc(raw));
    if (decoded is! Map<String, dynamic>) return raw;
    decoded['id'] = newId;
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  void _logScanError(String path, Object error) {
    if (kDebugMode) {
      debugPrint('ThemeRegistryService: skipped $path ($error)');
    }
  }
}

class _ResolvedImportDestination {
  const _ResolvedImportDestination({
    required this.file,
    required this.reused,
    this.renamedId,
  });

  final File file;
  final bool reused;
  final String? renamedId;
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
