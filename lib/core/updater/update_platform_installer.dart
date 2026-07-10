import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_updater_service.dart';
import 'installers/linux_appimage_installer.dart';
import 'installers/macos_sparkle_installer.dart';
import 'installers/update_install_context.dart';
import 'installers/windows_exe_installer.dart';

/// Selects and runs the platform-specific in-place update installer.
class UpdatePlatformInstaller {
  const UpdatePlatformInstaller._(this._delegate);

  final Future<void> Function(File verifiedPackage) _delegate;

  Future<void> install(File verifiedPackage) => _delegate(verifiedPackage);

  factory UpdatePlatformInstaller.forCurrentPlatform({
    UpdateInstallContext? context,
  }) {
    final ctx = context ?? UpdateInstallContext.current();

    if (ctx.isManagedPackage) {
      return UpdatePlatformInstaller._((file) async {
        throw PackageManagerUpdateRequiredException(
          manager: ctx.isSnap ? 'snap' : 'flatpak',
          hint: ctx.isSnap
              ? 'Updates for the Snap build must be installed with: snap refresh'
              : 'Updates for the Flatpak build must be installed with: flatpak update',
        );
      });
    }

    if (Platform.isLinux) {
      return UpdatePlatformInstaller._((file) async {
        final lower = file.path.toLowerCase();
        if (lower.endsWith('.appimage') || ctx.isLinuxAppImage) {
          await LinuxAppImageInstaller(context: ctx).install(file);
          return;
        }
        if (lower.endsWith('.zip')) {
          await LinuxAppImageInstaller.installLinuxZipBundle(
            context: ctx,
            zipFile: file,
          );
          return;
        }
        throw AppUpdaterException(
          'Unsupported Linux update package: ${p.basename(file.path)}',
        );
      });
    }

    if (Platform.isWindows) {
      return UpdatePlatformInstaller._(
        (file) => WindowsExeInstaller(context: ctx).install(file),
      );
    }

    if (Platform.isMacOS) {
      return UpdatePlatformInstaller._(
        (file) => MacosSparkleInstaller(context: ctx).install(file),
      );
    }

    return UpdatePlatformInstaller._((_) async {
      throw AppUpdaterException(
        'In-app installation is not supported on ${Platform.operatingSystem}',
      );
    });
  }
}
