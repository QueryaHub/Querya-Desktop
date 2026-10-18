import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:querya_desktop/core/util/log_ignored.dart';

import '../app_updater_service.dart';
import 'update_install_context.dart';
import 'update_install_utils.dart';

/// macOS `.app` bundle replacement with Gatekeeper codesign verification.
///
/// Sparkle integration can wrap this path later; for now we verify `codesign`
/// on the downloaded bundle before swapping it in place.
class MacosSparkleInstaller {
  MacosSparkleInstaller({
    required this.context,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
        runProcess,
  }) : _runProcess = runProcess ?? Process.run;

  final UpdateInstallContext context;
  final Future<ProcessResult> Function(String, List<String>) _runProcess;

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
      await _verifySameSigner(installed: targetApp, update: found.path);
      newApp = found;
    } catch (_) {
      // The app keeps running: do not leave the extracted update behind.
      try {
        await extractDir.delete(recursive: true);
      } catch (e) {
        logIgnored('macos_sparkle_installer', e);
      }
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

  /// `codesign --verify` only proves the seal is intact: any validly signed
  /// bundle, even ad-hoc, passed and replaced the app. The update must also
  /// carry the Team ID of the installed app (#1588).
  Future<void> _verifySameSigner({
    required String installed,
    required String update,
  }) async {
    final problem = signerMismatchProblem(
      installedTeam: await _teamId(installed),
      updateTeam: await _teamId(update),
    );
    if (problem != null) throw AppUpdaterException(problem);
  }

  /// The bundle's Team ID, or null when it has none (ad-hoc or unsigned:
  /// `codesign -dv` fails or prints `TeamIdentifier=not set`).
  Future<String?> _teamId(String bundle) async {
    final result =
        await _runProcess('codesign', ['-dv', '--verbose=4', bundle]);
    if (result.exitCode != 0) return null;
    // codesign writes the details to stderr.
    return parseCodesignTeamId('${result.stderr}\n${result.stdout}');
  }

  Future<void> _verifyCodesign(Directory appBundle) async {
    final result = await _runProcess(
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

/// The `TeamIdentifier=` of `codesign -dv` output, or null for none / `not set`.
String? parseCodesignTeamId(String codesignOutput) {
  final match = RegExp(r'^TeamIdentifier=(.*)$', multiLine: true)
      .firstMatch(codesignOutput);
  final id = match?.group(1)?.trim();
  if (id == null || id.isEmpty || id == 'not set') return null;
  return id;
}

/// Why an update signed by [updateTeam] may not replace an app signed by
/// [installedTeam], or null when it may.
///
/// An installed app with no Team ID (the unsigned or ad-hoc build) has
/// nothing to compare with: there the SHA-256 from the release's
/// `SHA256SUMS.txt`, checked before this, is the check.
String? signerMismatchProblem({
  required String? installedTeam,
  required String? updateTeam,
}) {
  if (installedTeam == null || updateTeam == installedTeam) return null;
  return updateTeam == null
      ? 'The downloaded update is not signed by the developer of the installed '
          'app (Team ID $installedTeam). Installation aborted.'
      : 'The downloaded update is signed by a different developer (Team ID '
          '$updateTeam, expected $installedTeam). Installation aborted.';
}
