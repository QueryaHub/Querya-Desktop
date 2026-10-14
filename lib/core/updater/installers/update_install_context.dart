import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_updater_service.dart';

/// Runtime packaging context for in-place update installation.
class UpdateInstallContext {
  const UpdateInstallContext({
    required this.environment,
    required this.resolvedExecutable,
    this.fileExists,
    this.listDirectory,
    this.isDirectoryWritable,
  });

  final Map<String, String> environment;
  final String resolvedExecutable;

  /// File-system probes, replaceable in tests; default to the real disk.
  final bool Function(String path)? fileExists;
  final List<String> Function(String dir)? listDirectory;
  final bool Function(String dir)? isDirectoryWritable;

  /// Where the `.deb`, `.rpm` and AUR packages put the bundle.
  static const linuxSystemBundleRoot = '/opt/querya-desktop';

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
      Platform.isLinux && environment.containsKey('FLATPAK_ID');

  /// The system package manager that owns the running bundle: `pacman` (AUR),
  /// `dpkg` (`.deb`) or `rpm` (`.rpm`); null for a portable bundle, an
  /// AppImage, Snap or Flatpak.
  ///
  /// Those packages install the bundle into [linuxSystemBundleRoot], owned by
  /// root: an in-place update cannot write there, quits the app and leaves it
  /// not running (seen with the AUR package, 0.4.18 -> 0.4.19).
  String? get linuxSystemPackageManager {
    if (!Platform.isLinux || isSnap || isFlatpak || isLinuxAppImage) {
      return null;
    }
    if (linuxBundleRoot != linuxSystemBundleRoot) return null;
    final exists = fileExists ?? (path) => File(path).existsSync();
    final list = listDirectory ?? _listDirectory;
    if (list('/var/lib/pacman/local')
        .any((name) => name.startsWith('querya-desktop-'))) {
      return 'pacman';
    }
    if (exists('/var/lib/dpkg/info/querya-desktop.list')) return 'dpkg';
    if (exists('/usr/bin/rpm') || exists('/bin/rpm')) return 'rpm';
    return null;
  }

  /// True when the Linux bundle directory exists but this user cannot write
  /// it, whoever installed it: an in-place update would fail half-way.
  bool get isLinuxBundleReadOnly {
    if (!Platform.isLinux || isSnap || isFlatpak || isLinuxAppImage) {
      return false;
    }
    final root = linuxBundleRoot;
    if (root == null) return false;
    return !(isDirectoryWritable ?? _isDirectoryWritable)(root);
  }

  bool get isManagedPackage =>
      isSnap ||
      isFlatpak ||
      linuxSystemPackageManager != null ||
      isLinuxBundleReadOnly;

  /// Command the user should run when [isManagedPackage] is true; null when
  /// there is no single command (a read-only bundle of unknown origin).
  String? get packageManagerUpdateCommand {
    if (isSnap) return 'snap refresh';
    if (isFlatpak) return 'flatpak update';
    return switch (linuxSystemPackageManager) {
      'pacman' => 'yay -Syu querya-desktop',
      'dpkg' => 'sudo apt update && sudo apt install --only-upgrade querya-desktop',
      'rpm' => 'sudo dnf upgrade querya-desktop',
      _ => null,
    };
  }

  /// Why in-app install is blocked and what to do, for messages.
  String get managedUpdateHint {
    if (isSnap) {
      return 'Updates for the Snap build must be installed with: snap refresh';
    }
    if (isFlatpak) {
      return 'Updates for the Flatpak build must be installed with: flatpak update';
    }
    final command = packageManagerUpdateCommand;
    final manager = switch (linuxSystemPackageManager) {
      'pacman' => 'the AUR package',
      'dpkg' => 'the .deb package',
      'rpm' => 'the .rpm package',
      _ => null,
    };
    if (manager != null && command != null) {
      return 'Querya Desktop was installed from $manager; update it with: $command';
    }
    return 'Querya Desktop is installed in ${linuxBundleRoot ?? 'a folder'}, '
        'which this user cannot write. Update it the way it was installed, '
        'or download the new version from the release page.';
  }

  static List<String> _listDirectory(String dir) {
    try {
      return [
        for (final e in Directory(dir).listSync(followLinks: false))
          p.basename(e.path),
      ];
    } on FileSystemException {
      return const [];
    }
  }

  /// A missing directory counts as writable: nothing to protect, and tests
  /// use made-up paths.
  static bool _isDirectoryWritable(String dir) {
    if (!Directory(dir).existsSync()) return true;
    final probe = File(p.join(dir, '.querya-write-probe-$pid'));
    try {
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

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
