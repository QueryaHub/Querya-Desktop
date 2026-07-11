import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_updater_service.dart';
import 'update_install_context.dart';
import 'update_install_utils.dart';

/// Windows silent installer launch and zip bundle replacement.
class WindowsExeInstaller {
  WindowsExeInstaller({required this.context});

  final UpdateInstallContext context;

  Future<void> install(File package) async {
    final lower = package.path.toLowerCase();
    if (lower.endsWith('.exe') && _looksLikeSetupInstaller(package)) {
      await Process.start(
        package.path,
        const ['/SILENT', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }

    if (lower.endsWith('.zip')) {
      await _installZipBundle(package);
      return;
    }

    throw AppUpdaterException(
      'Unsupported Windows update package: ${p.basename(package.path)}',
    );
  }

  Future<void> _installZipBundle(File zipFile) async {
    final targetDir = context.windowsInstallRoot;
    if (targetDir == null || targetDir.isEmpty) {
      throw const AppUpdaterException(
        'Could not determine the Windows install directory for in-place update',
      );
    }

    final tempRoot = await getTemporaryDirectory();
    final extractDir = Directory(
      p.join(tempRoot.path, 'querya-update-${DateTime.now().millisecondsSinceEpoch}'),
    );
    await extractZipSecurely(zipFile: zipFile, destinationDir: extractDir);

    final executableName = p.basename(context.resolvedExecutable);
    final batchFile = File(p.join(tempRoot.path, 'querya-win-update-$pid.bat'));
    await batchFile.writeAsString(
      buildWindowsReplaceBatch(
        pid: pid,
        sourceDir: extractDir.path,
        targetDir: targetDir,
        executable: executableName,
      ),
    );
    await launchDetachedScript(batchFile.path, const []);
    exit(0);
  }

  bool _looksLikeSetupInstaller(File file) {
    final name = p.basename(file.path).toLowerCase();
    if (name == 'querya_desktop.exe') return false;
    return name.endsWith('.exe');
  }
}
