import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_updater_service.dart';
import 'update_install_context.dart';
import 'update_install_utils.dart';

/// Linux in-place updates for AppImage builds and extracted bundle zips.
class LinuxAppImageInstaller {
  LinuxAppImageInstaller({required this.context});

  final UpdateInstallContext context;

  Future<void> install(File package) async {
    final lower = package.path.toLowerCase();
    if (lower.endsWith('.zip')) {
      await installLinuxZipBundle(context: context, zipFile: package);
      return;
    }
    if (lower.endsWith('.appimage')) {
      await _installAppImageFile(package);
      return;
    }
    throw AppUpdaterException(
      'Unsupported Linux update package: ${p.basename(package.path)}',
    );
  }

  static Future<void> installLinuxZipBundle({
    required UpdateInstallContext context,
    required File zipFile,
  }) async {
    final tempRoot = await getTemporaryDirectory();
    final extractDir = Directory(
      p.join(tempRoot.path, 'querya-update-${DateTime.now().millisecondsSinceEpoch}'),
    );

    try {
      await extractZipSecurely(zipFile: zipFile, destinationDir: extractDir);

      if (context.isLinuxAppImage) {
        final appImage = await findAppImageInDirectory(extractDir);
        if (appImage != null) {
          await LinuxAppImageInstaller(context: context)
              ._installAppImageFile(appImage);
          return;
        }
      }

      final targetDir = context.linuxBundleRoot;
      if (targetDir == null || targetDir.isEmpty) {
        throw const AppUpdaterException(
          'Could not determine the Linux install directory for in-place update',
        );
      }

      final executable = context.resolvedExecutable;
      final scriptFile = File(
        p.join(tempRoot.path, 'querya-linux-update-$pid.sh'),
      );
      await scriptFile.writeAsString(
        buildLinuxBundleReplaceScript(
          pid: pid,
          sourceDir: extractDir.path,
          targetDir: targetDir,
          executable: executable,
        ),
      );
      await launchDetachedScript(scriptFile.path, const []);
      exit(0);
    } finally {
      // Extract dir is consumed by the detached script; leave cleanup to the script/OS.
    }
  }

  Future<void> _installAppImageFile(File newAppImage) async {
    final target = context.appImagePath;
    if (target == null || target.isEmpty) {
      throw const AppUpdaterException(
        'APPIMAGE path is not available; cannot perform in-place AppImage update',
      );
    }

    final targetFile = File(target);
    final staged = File('$target.new');
    if (await staged.exists()) {
      await staged.delete();
    }
    await newAppImage.copy(staged.path);
    await Process.run('chmod', ['+x', staged.path]);

    final tempRoot = await getTemporaryDirectory();
    final scriptFile = File(p.join(tempRoot.path, 'querya-appimage-update-$pid.sh'));
    await scriptFile.writeAsString(
      buildLinuxAppImageReplaceScript(
        pid: pid,
        targetAppImage: targetFile.path,
        stagedAppImage: staged.path,
      ),
    );
    await launchDetachedScript(scriptFile.path, const []);
    exit(0);
  }
}
