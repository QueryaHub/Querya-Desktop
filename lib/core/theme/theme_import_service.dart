import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/storage/app_data_root.dart';

import 'parser/vscode_theme_manifest.dart';
import 'theme_definition.dart';


/// Result of copying a theme file into the user themes directory.
sealed class ThemeDefinitionImportResult {
  const ThemeDefinitionImportResult();
}

final class ThemeDefinitionImportSuccess extends ThemeDefinitionImportResult {
  const ThemeDefinitionImportSuccess({
    required this.definition,
    required this.reusedExisting,
  });

  final ThemeDefinition definition;
  final bool reusedExisting;
}

final class ThemeDefinitionImportFailure extends ThemeDefinitionImportResult {
  const ThemeDefinitionImportFailure(this.message);
  final String message;
}

/// Parses and persists an imported VS Code theme under app support.
abstract final class ThemeImportService {
  static const String legacyImportedThemeId = 'imported';
  static const String storedFileName = 'imported.json';

  /// Lowercase slug for VS Code theme filenames.
  static String slugifyThemeName(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'vscode-theme' : slug;
  }

  /// Safe basename for theme files (without extension).
  static String safeThemeFileBase(String value) {
    final safe = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return safe.isEmpty ? 'theme' : safe;
  }

  /// Path to the persisted legacy import copy under app support.
  static Future<File> persistedImportFile() => _storedThemeFile();


  /// Reloads colors from the persisted import file, if present.
  static Future<Map<String, String>?> loadPersistedColors() async {
    final manifest = await loadPersistedManifest();
    if (manifest == null || manifest.colors.isEmpty) return null;
    return manifest.colors;
  }

  /// Reloads `tokenColors` from the persisted import file, if present.
  static Future<List<TokenColorRule>> loadPersistedTokenColors() async {
    final manifest = await loadPersistedManifest();
    return manifest?.tokenColors ?? const [];
  }

  /// Full parsed manifest from the persisted import copy.
  static Future<VsCodeThemeManifest?> loadPersistedManifest() async {
    final file = await _storedThemeFile();
    if (!await file.exists()) return null;
    try {
      return VsCodeThemeManifest.fromJsonString(await file.readAsString());
    } on Object {
      return null;
    }
  }

  static Future<void> deletePersistedImport() async {
    final file = await _storedThemeFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<File> _storedThemeFile() async {
    final support = await AppDataRoot.applicationSupportDirectory();
    return File(p.join(support.path, 'themes', storedFileName));
  }
}
