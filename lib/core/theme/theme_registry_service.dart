import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'parser/jsonc_preprocessor.dart';
import 'parser/querya_theme_manifest.dart';
import 'theme_definition.dart';
import 'theme_paths.dart';

/// Scans theme directories and exposes lightweight [ThemeDefinition] metadata.
class ThemeRegistryService {
  ThemeRegistryService({
    Future<Directory> Function()? userThemesDirectory,
    Future<Directory> Function()? importedThemesDirectory,
  })  : _userThemesDirectory =
            userThemesDirectory ?? ThemePaths.userThemesDirectory,
        _importedThemesDirectory =
            importedThemesDirectory ?? ThemePaths.importedThemesDirectory;

  final Future<Directory> Function() _userThemesDirectory;
  final Future<Directory> Function() _importedThemesDirectory;

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
