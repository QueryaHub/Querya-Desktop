import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'parser/vscode_theme_manifest.dart';

/// Result of importing a VS Code theme file.
sealed class ThemeImportResult {
  const ThemeImportResult();
}

class ThemeImportSuccess extends ThemeImportResult {
  const ThemeImportSuccess({
    required this.name,
    required this.isDark,
    required this.colors,
    required this.storedPath,
  });

  final String name;
  final bool isDark;
  final Map<String, String> colors;
  final String storedPath;
}

class ThemeImportFailure extends ThemeImportResult {
  const ThemeImportFailure(this.message);
  final String message;
}

/// Parses and persists an imported VS Code theme under app support.
abstract final class ThemeImportService {
  static const String _storedFileName = 'imported.json';

  /// Reads [sourcePath], parses JSON/JSONC, copies to app data, returns colors.
  static Future<ThemeImportResult> importFromPath(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        return const ThemeImportFailure('Theme file not found.');
      }
      final raw = await source.readAsString();
      final manifest = VsCodeThemeManifest.fromJsonString(raw);
      if (manifest.colors.isEmpty) {
        return const ThemeImportFailure(
          'Theme file has no "colors" section to import.',
        );
      }

      final storedFile = await _storedThemeFile();
      await storedFile.parent.create(recursive: true);
      await storedFile.writeAsString(raw);

      final name = manifest.name?.trim().isNotEmpty == true
          ? manifest.name!.trim()
          : p.basenameWithoutExtension(sourcePath);

      return ThemeImportSuccess(
        name: name,
        isDark: manifest.isDark || !manifest.isLight,
        colors: Map.unmodifiable(manifest.colors),
        storedPath: storedFile.path,
      );
    } on VsCodeThemeParseException catch (e) {
      return ThemeImportFailure(e.message);
    } on FormatException catch (e) {
      return ThemeImportFailure(e.message);
    } on IOException catch (e) {
      return ThemeImportFailure(e.toString());
    } on Object catch (e) {
      return ThemeImportFailure(e.toString());
    }
  }

  /// Reloads colors from the persisted import file, if present.
  static Future<Map<String, String>?> loadPersistedColors() async {
    final file = await _storedThemeFile();
    if (!await file.exists()) return null;
    try {
      final manifest =
          VsCodeThemeManifest.fromJsonString(await file.readAsString());
      if (manifest.colors.isEmpty) return null;
      return manifest.colors;
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
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'themes', _storedFileName));
  }
}
