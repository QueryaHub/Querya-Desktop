import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralizes extension file locations.
abstract final class ExtensionPaths {
  static const _extensionsSegment = 'extensions';

  @visibleForTesting
  static Directory? mockExtensionsDirectory;

  /// Returns `~/.querya/extensions` on Linux/Mac, or equivalent `USERPROFILE\.querya\extensions` on Windows.
  /// Falls back to application support directory if HOME is unavailable.
  static Future<Directory> extensionsDirectory() async {
    if (mockExtensionsDirectory != null) {
      return mockExtensionsDirectory!;
    }
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, _extensionsSegment));
    }
    return Directory(p.join(home, '.querya', _extensionsSegment));
  }

  /// Creates the extensions directory if it doesn't exist.
  static Future<Directory> ensureExtensionsDirectory() async {
    final dir = await extensionsDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
