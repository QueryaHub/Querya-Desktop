import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'parser/jsonc_preprocessor.dart';
import 'parser/querya_theme_from_manifest.dart';
import 'parser/querya_theme_from_vscode.dart';
import 'parser/querya_theme_manifest.dart';
import 'parser/vscode_theme_manifest.dart';
import 'querya_theme.dart';
import 'theme_definition.dart';
import 'theme_load_result.dart';
import 'theme_paths.dart';

/// Scans theme directories and exposes lightweight [ThemeDefinition] metadata.
class ThemeRegistryService {
  ThemeRegistryService({
    Future<Directory> Function()? userThemesDirectory,
    Future<Directory> Function()? importedThemesDirectory,
    int maxCacheEntries = 16,
  })  : _userThemesDirectory =
            userThemesDirectory ?? ThemePaths.userThemesDirectory,
        _importedThemesDirectory =
            importedThemesDirectory ?? ThemePaths.importedThemesDirectory,
        _themeCache = _ThemeLruCache(maxEntries: maxCacheEntries);

  static const defaultMaxCacheEntries = 16;

  final Future<Directory> Function() _userThemesDirectory;
  final Future<Directory> Function() _importedThemesDirectory;
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

    definitions.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List.unmodifiable(definitions);
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

    final file = File(path);
    if (!await file.exists()) {
      return ThemeLoadFailure(
        definition: definition,
        message: 'Theme file not found.',
      );
    }

    final cacheKey = definition.stableCacheKey;
    final cachedTheme = _themeCache.get(cacheKey);
    if (cachedTheme != null) {
      return ThemeLoadSuccess(definition: definition, theme: cachedTheme);
    }

    try {
      final raw = await file.readAsString();
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
        return _customDefinition(
          json: json,
          file: file,
          source: source,
          lastModified: stat.modified,
          contentHash: hash,
        );
      }

      return _vscodeDefinition(
        json: json,
        file: file,
        source: source,
        lastModified: stat.modified,
        contentHash: hash,
      );
    } on Object catch (e) {
      _logScanError(file.path, e);
      return null;
    }
  }

  ThemeDefinition? _customDefinition({
    required Map<String, dynamic> json,
    required File file,
    required ThemeSource source,
    required DateTime lastModified,
    required String contentHash,
  }) {
    final id = json['id']?.toString().trim();
    final name = json['name']?.toString().trim();
    final type = json['type']?.toString().trim().toLowerCase();

    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      _logScanError(file.path, 'Missing required custom theme fields');
      return null;
    }
    if (type != 'dark' && type != 'light') {
      _logScanError(file.path, 'Invalid custom theme type "$type"');
      return null;
    }

    return ThemeDefinition(
      id: id,
      name: name,
      source: source,
      format: ThemeFormat.queryaCustom,
      isDark: type == 'dark',
      path: file.path,
      lastModified: lastModified,
      contentHash: contentHash,
    );
  }

  ThemeDefinition? _vscodeDefinition({
    required Map<String, dynamic> json,
    required File file,
    required ThemeSource source,
    required DateTime lastModified,
    required String contentHash,
  }) {
    final fileId = p.basenameWithoutExtension(file.path);
    final rawName = json['name']?.toString().trim();
    final name = rawName != null && rawName.isNotEmpty ? rawName : fileId;
    final type = json['type']?.toString().trim().toLowerCase();

    return ThemeDefinition(
      id: fileId,
      name: name,
      source: source,
      format: ThemeFormat.vscode,
      isDark: type == 'dark',
      path: file.path,
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
