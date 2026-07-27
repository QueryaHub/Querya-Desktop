import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/updater/installers/update_install_context.dart';
import 'package:querya_desktop/core/updater/update_manifest.dart';

/// Ordered filename suffixes to try when picking a GitHub Release asset.
///
/// Prefer the packaging family of the running binary so portable users are not
/// switched onto installers (and vice versa).
List<String> preferredUpdateAssetSuffixes(
  UpdateInstallContext context, {
  String? operatingSystem,
  bool Function(String path)? fileExists,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final exists = fileExists ?? ((path) => File(path).existsSync());

  switch (os) {
    case 'linux':
      if (context.isSnap || context.isFlatpak) {
        // In-app install is blocked; still prefer zip if selection is asked.
        return const ['-linux.zip'];
      }
      if (context.appImagePath != null) {
        return const ['-linux.AppImage', '-linux.appimage', '-linux.zip'];
      }
      return const ['-linux.zip', '-linux.AppImage', '-linux.appimage'];
    case 'windows':
      if (_looksLikeWindowsSetupInstall(context, exists)) {
        return const ['-windows-setup.exe', '-windows.zip'];
      }
      return const ['-windows.zip', '-windows-setup.exe'];
    case 'macos':
      return const ['-macos.zip'];
    default:
      return const [];
  }
}

/// Picks the first manifest asset whose name ends with a preferred suffix.
UpdateAsset? selectUpdateAsset(
  UpdateManifest manifest,
  UpdateInstallContext context, {
  String? operatingSystem,
  bool Function(String path)? fileExists,
}) {
  final suffixes = preferredUpdateAssetSuffixes(
    context,
    operatingSystem: operatingSystem,
    fileExists: fileExists,
  );
  for (final suffix in suffixes) {
    final needle = suffix.toLowerCase();
    for (final asset in manifest.assets) {
      if (asset.name.toLowerCase().endsWith(needle)) return asset;
    }
  }
  return null;
}

bool _looksLikeWindowsSetupInstall(
  UpdateInstallContext context,
  bool Function(String path) fileExists,
) {
  final root = p.dirname(context.resolvedExecutable);
  // Inno Setup default uninstaller next to the app.
  if (fileExists(p.join(root, 'unins000.exe'))) return true;
  final channel = context.environment['QUERYA_INSTALL_CHANNEL']?.toLowerCase();
  return channel == 'installer' || channel == 'setup';
}
