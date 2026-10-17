import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_updater_service.dart';
import 'update_install_context.dart';
import 'update_install_utils.dart';

/// macOS `.app` bundle replacement with Gatekeeper codesign verification.
///
/// Sparkle integration can wrap this path later; for now we verify `codesign`
/// on the downloaded bundle before swapping it in place.
class MacosSparkleInstaller {
  MacosSparkleInstaller({required this.context});

  final UpdateInstallContext context;

  Future<void> install(File package) async {
    final lower = package.path.toLowerCase();
    if (!lower.endsWith('.zip')) {
      throw AppUpdaterException(
        'Unsupported macOS update package: ${p.basename(package.path)}',
      );
    }

    final targetApp = context.macAppBundlePath;
    if (targetApp == null || targetApp.isEmpty) {
      throw const AppUpdaterException(
        'Could not locate the running .app bundle for in-place update',
      );
    }

    // Checked again here, right before the app quits for good (#1587).
    final problem = context.macAppBundleReplaceProblemFor(targetApp);
    if (problem != null) {
      throw PackageManagerUpdateRequiredException(
        manager: 'system',
        hint: problem,
      );
    }

    final tempRoot = await getTemporaryDirectory();
    final extractDir = Directory(
      p.join(tempRoot.path, 'querya-update-${DateTime.now().millisecondsSinceEpoch}'),
    );
    final Directory newApp;
    try {
      await extractZipSecurely(zipFile: package, destinationDir: extractDir);
      final found = await findMacAppBundleInDirectory(extractDir);
      if (found == null) {
        throw const AppUpdaterException(
          'Downloaded macOS update zip does not contain a .app bundle',
        );
      }
      await _verifyCodesign(found);
      newApp = found;
    } catch (_) {
      // The app keeps running: do not leave the extracted update behind.
      try {
        await extractDir.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }

    final scriptFile = File(p.join(tempRoot.path, 'querya-macos-update-$pid.sh'));
    await scriptFile.writeAsString(
      buildMacAppReplaceScript(
        pid: pid,
        newAppBundle: newApp.path,
        targetAppBundle: targetApp,
        executable: context.resolvedExecutable,
        workDir: extractDir.path,
      ),
    );
    await launchDetachedScript(scriptFile.path, const []);
    exit(0);
  }

  Future<void> _verifyCodesign(Directory appBundle) async {
    final result = await Process.run(
      'codesign',
      ['--verify', '--deep', '--strict', appBundle.path],
    );
    if (result.exitCode != 0) {
      final detail = (result.stderr as String?)?.trim();
      throw AppUpdaterException(
        detail == null || detail.isEmpty
            ? 'Gatekeeper verification failed for downloaded app bundle'
            : 'Gatekeeper verification failed: $detail',
      );
    }
  }
}
