import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralizes theme file locations under app support and legacy paths.
abstract final class ThemePaths {
  static const _themesSegment = 'themes';
  static const _importedSegment = 'imported';

  /// App support `themes/` directory. Does not create the directory.
  static Future<Directory> userThemesDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, _themesSegment));
  }

  /// App support `themes/imported/` directory. Does not create the directory.
  static Future<Directory> importedThemesDirectory() async {
    final themes = await userThemesDirectory();
    return Directory(p.join(themes.path, _importedSegment));
  }

  /// Creates app support `themes/` if missing.
  static Future<Directory> ensureUserThemesDirectory() async {
    final dir = await userThemesDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Creates app support `themes/imported/` if missing.
  static Future<Directory> ensureImportedThemesDirectory() async {
    final dir = await importedThemesDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Optional legacy `~/.querya/themes`. Does not create the directory.
  static Future<Directory?> legacyDotQueryaThemesDirectory() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return Directory(p.join(home, '.querya', _themesSegment));
  }
}
