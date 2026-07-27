import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves where Querya stores local profile data (DB, themes, extensions, logs).
///
/// Default: OS application-support paths.
/// Portable: when [envPortable] is truthy and/or a [sidecarDirName] folder exists
/// next to the binary (or `$APPIMAGE`), data goes under that folder.
///
/// Secrets still use the OS keyring via `flutter_secure_storage` (not redirected).
abstract final class AppDataRoot {
  static const envPortable = 'QUERYA_PORTABLE';
  static const sidecarDirName = 'QueryaData';

  @visibleForTesting
  static String? mockPortableRootPath;

  @visibleForTesting
  static String? mockInstallDirectory;

  @visibleForTesting
  static Map<String, String>? mockEnvironment;

  @visibleForTesting
  static void resetMocks() {
    mockPortableRootPath = null;
    mockInstallDirectory = null;
    mockEnvironment = null;
  }

  static Map<String, String> get _env =>
      mockEnvironment ?? Platform.environment;

  /// Directory containing the running binary, or the AppImage file's parent.
  static String? installDirectoryPath() {
    if (mockInstallDirectory != null) return mockInstallDirectory;
    final appImage = _env['APPIMAGE'];
    if (appImage != null && appImage.trim().isNotEmpty) {
      return p.dirname(appImage);
    }
    final exe = Platform.resolvedExecutable;
    if (exe.isEmpty) return null;
    return p.dirname(exe);
  }

  static bool envRequestsPortable() {
    final raw = _env[envPortable];
    if (raw == null) return false;
    final v = raw.trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes' || v == 'on';
  }

  /// Portable data root, or `null` when using normal OS support paths.
  ///
  /// When [envPortable] is set, creates [sidecarDirName] next to the install
  /// directory if it does not exist yet.
  static Future<Directory?> resolvePortableRoot() async {
    if (mockPortableRootPath != null) {
      return Directory(mockPortableRootPath!);
    }

    final installDir = installDirectoryPath();
    if (installDir == null || installDir.isEmpty) return null;

    final sidecar = Directory(p.join(installDir, sidecarDirName));
    final forced = envRequestsPortable();

    if (forced) {
      if (!await sidecar.exists()) {
        await sidecar.create(recursive: true);
      }
      return sidecar;
    }

    if (await sidecar.exists()) {
      return sidecar;
    }
    return null;
  }

  static Future<bool> isPortableMode() async =>
      (await resolvePortableRoot()) != null;

  /// Application-support equivalent: portable root or [getApplicationSupportDirectory].
  static Future<Directory> applicationSupportDirectory() async {
    final portable = await resolvePortableRoot();
    if (portable != null) return portable;
    return getApplicationSupportDirectory();
  }
}
