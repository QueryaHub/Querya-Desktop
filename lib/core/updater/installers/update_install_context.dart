import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_updater_service.dart';

/// Runtime packaging context for in-place update installation.
class UpdateInstallContext {
  const UpdateInstallContext({
    required this.environment,
    required this.resolvedExecutable,
  });

  final Map<String, String> environment;
  final String resolvedExecutable;

  factory UpdateInstallContext.current() {
    return UpdateInstallContext(
      environment: Map.unmodifiable(Platform.environment),
      resolvedExecutable: Platform.resolvedExecutable,
    );
  }

  String? get appImagePath {
    final fromEnv = environment['APPIMAGE'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return null;
  }

  bool get isLinuxAppImage => Platform.isLinux && appImagePath != null;

  bool get isSnap =>
      Platform.isLinux && environment.containsKey('SNAP');

  bool get isFlatpak =>
      Platform.isLinux &&
      (environment.containsKey('FLATPAK_ID') ||
          environment.containsKey('container'));

  bool get isManagedPackage => isSnap || isFlatpak;

  String? get linuxBundleRoot {
    if (!Platform.isLinux) return null;
    return p.dirname(resolvedExecutable);
  }

  String? get windowsInstallRoot {
    if (!Platform.isWindows) return null;
    return p.dirname(resolvedExecutable);
  }

  String? get macAppBundlePath {
    if (!Platform.isMacOS) return null;
    return macAppBundlePathFromExecutable(resolvedExecutable);
  }

  /// Locates the enclosing `.app` bundle for a macOS executable path.
  static String? macAppBundlePathFromExecutable(String executable) {
    var dir = p.dirname(executable);
    while (dir.length > 1 && dir != '/') {
      if (p.basename(dir).endsWith('.app')) return dir;
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    return null;
  }
}

/// Thrown when updates must be applied through the system package manager.
class PackageManagerUpdateRequiredException extends AppUpdaterException {
  PackageManagerUpdateRequiredException({
    required this.manager,
    required this.hint,
  }) : super(hint);

  final String manager;
  final String hint;
}
