import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/storage/app_data_root.dart';

/// Centralizes extension file locations.
abstract final class ExtensionPaths {
  static const _extensionsSegment = 'extensions';

  @visibleForTesting
  static Directory? mockExtensionsDirectory;

  /// Portable: `{QueryaData}/extensions`.
  /// Otherwise: `~/.querya/extensions` (or app-support fallback if HOME is missing).
  static Future<Directory> extensionsDirectory() async {
    if (mockExtensionsDirectory != null) {
      return mockExtensionsDirectory!;
    }
    final portable = await AppDataRoot.resolvePortableRoot();
    if (portable != null) {
      return Directory(p.join(portable.path, _extensionsSegment));
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      final support = await AppDataRoot.applicationSupportDirectory();
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
