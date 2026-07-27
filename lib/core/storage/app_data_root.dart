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

  /// Current Linux GTK / XDG application id.
  static const linuxApplicationId = 'com.queryahub.querya_desktop';

  /// Current macOS bundle identifier.
  static const macBundleId = 'com.queryahub.queryaDesktop';

  /// Previous placeholder ids (pre-#385) used for one-shot support-dir migration.
  static const legacyLinuxApplicationId = 'com.example.querya_desktop';
  static const legacyMacBundleId = 'com.example.queryaDesktop';
  static const legacyWindowsCompany = 'com.example';
  static const legacyWindowsProduct = 'querya_desktop';

  @visibleForTesting
  static String? mockPortableRootPath;

  @visibleForTesting
  static String? mockInstallDirectory;

  @visibleForTesting
  static Map<String, String>? mockEnvironment;

  @visibleForTesting
  static List<Directory>? mockLegacySupportCandidates;

  @visibleForTesting
  static void resetMocks() {
    mockPortableRootPath = null;
    mockInstallDirectory = null;
    mockEnvironment = null;
    mockLegacySupportCandidates = null;
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
  ///
  /// When not portable, copies data once from legacy `com.example.*` support
  /// paths if the new location has no `querya.db` yet.
  static Future<Directory> applicationSupportDirectory() async {
    final portable = await resolvePortableRoot();
    if (portable != null) return portable;

    final support = await getApplicationSupportDirectory();
    await migrateLegacySupportIfNeeded(newSupport: support);
    return support;
  }

  /// One-shot copy from [legacySupportCandidates] into [newSupport].
  @visibleForTesting
  static Future<bool> migrateLegacySupportIfNeeded({
    required Directory newSupport,
    List<Directory>? legacyCandidates,
  }) async {
    final newDb = File(p.join(newSupport.path, 'querya_desktop', 'querya.db'));
    if (await newDb.exists()) return false;

    final candidates = legacyCandidates ??
        mockLegacySupportCandidates ??
        await legacySupportCandidates();

    for (final legacy in candidates) {
      if (p.equals(legacy.path, newSupport.path)) continue;
      final legacyDb =
          File(p.join(legacy.path, 'querya_desktop', 'querya.db'));
      if (!await legacyDb.exists()) continue;
      await _copyDirectory(legacy, newSupport);
      debugPrint(
        'AppDataRoot: migrated profile data from ${legacy.path} → ${newSupport.path}',
      );
      return true;
    }
    return false;
  }

  @visibleForTesting
  static Future<List<Directory>> legacySupportCandidates() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return mockLegacySupportCandidates ?? const [];
    }

    final home = _env['HOME'] ?? _env['USERPROFILE'];
    if (home == null || home.isEmpty) return const [];

    if (Platform.isLinux) {
      final xdg = _env['XDG_DATA_HOME'];
      final base =
          (xdg != null && xdg.isNotEmpty) ? xdg : p.join(home, '.local', 'share');
      return [Directory(p.join(base, legacyLinuxApplicationId))];
    }
    if (Platform.isMacOS) {
      return [
        Directory(
          p.join(home, 'Library', 'Application Support', legacyMacBundleId),
        ),
        // Older docs incorrectly used the Linux-style id on macOS.
        Directory(
          p.join(
            home,
            'Library',
            'Application Support',
            legacyLinuxApplicationId,
          ),
        ),
      ];
    }
    if (Platform.isWindows) {
      final appData =
          _env['APPDATA'] ?? p.join(home, 'AppData', 'Roaming');
      return [
        Directory(
          p.join(appData, legacyWindowsCompany, legacyWindowsProduct),
        ),
      ];
    }
    return const [];
  }

  static Future<void> _copyDirectory(Directory from, Directory to) async {
    if (!await to.exists()) {
      await to.create(recursive: true);
    }
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: from.path);
      final destPath = p.join(to.path, relative);
      if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      } else if (entity is File) {
        await File(destPath).parent.create(recursive: true);
        await entity.copy(destPath);
      }
    }
  }
}
