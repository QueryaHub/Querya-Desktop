import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/app_settings.dart';
import 'github_releases_client.dart';
import 'installers/update_install_context.dart';
import 'sha256_checksums.dart';
import 'update_asset_selection.dart';
import 'update_manifest.dart';
import 'update_platform_installer.dart';
import 'update_version.dart';

/// Core service for checking GitHub Releases and downloading verified update artifacts.
class AppUpdaterService {
  AppUpdaterService({
    GitHubReleasesClient? releasesClient,
    http.Client? downloadClient,
    Future<PackageInfo> Function()? packageInfoProvider,
    AppSettings? settings,
  })  : _releasesClient = releasesClient ?? GitHubReleasesClient(),
        _downloadClient = downloadClient ?? http.Client(),
        _packageInfoProvider =
            packageInfoProvider ?? (() => PackageInfo.fromPlatform()),
        _settings = settings ?? AppSettings.instance;

  final GitHubReleasesClient _releasesClient;
  final http.Client _downloadClient;
  final Future<PackageInfo> Function() _packageInfoProvider;
  final AppSettings _settings;

  static final AppUpdaterService instance = AppUpdaterService();

  /// Checks GitHub Releases for a newer version than the running app.
  ///
  /// When [background] is true, errors are returned in [UpdateCheckResult.errorMessage]
  /// instead of being rethrown (for silent startup checks).
  Future<UpdateCheckResult> checkForUpdates({bool background = false}) async {
    try {
      final packageInfo = await _packageInfoProvider();
      final currentRaw = packageInfo.version;
      final currentVersion = UpdateVersion.tryParse(currentRaw);
      if (currentVersion == null) {
        throw AppUpdaterException('Invalid current app version: $currentRaw');
      }

      final channel = await _settings.getUpdateChannel();
      final manifest = await _releasesClient.fetchLatest(channel: channel);
      final candidateVersion = UpdateVersion.tryParse(manifest.version);
      if (candidateVersion == null) {
        throw AppUpdaterException(
          'Invalid release version tag: ${manifest.version}',
        );
      }

      final allowPreRelease = channel == UpdateChannel.dev;
      final available = UpdateVersion.isUpdateAvailable(
        current: currentVersion,
        candidate: candidateVersion,
        allowPreRelease: allowPreRelease,
      );

      if (!available) {
        return UpdateCheckResult(currentVersion: currentRaw);
      }

      return UpdateCheckResult(
        currentVersion: currentRaw,
        availableUpdate: manifest,
      );
    } on AppUpdaterException catch (e) {
      if (background) {
        return UpdateCheckResult(
          currentVersion: '',
          errorMessage: e.message,
        );
      }
      rethrow;
    } on GitHubReleasesException catch (e) {
      if (background) {
        return UpdateCheckResult(
          currentVersion: '',
          errorMessage: e.message,
        );
      }
      throw AppUpdaterException(e.message, cause: e);
    } catch (e, st) {
      debugPrint('AppUpdaterService.checkForUpdates: $e\n$st');
      if (background) {
        return UpdateCheckResult(
          currentVersion: '',
          errorMessage: e.toString(),
        );
      }
      rethrow;
    }
  }

  /// Runs a background update check on startup when enabled in Preferences.
  Future<UpdateCheckResult?> maybeCheckOnStartup() async {
    final enabled = await _settings.getCheckForUpdatesOnStartup();
    if (!enabled) return null;
    return checkForUpdates(background: true);
  }

  /// Downloads [asset] to a temp file and verifies SHA256 before returning the path.
  ///
  /// When [manifest] is provided, its [UpdateManifest.checksumsUrl] is used to load
  /// `SHA256SUMS.txt` before downloading the binary.
  Future<File> downloadAsset(
    UpdateAsset asset, {
    UpdateManifest? manifest,
    UpdateDownloadProgressCallback? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final checksums = await _resolveChecksums(asset: asset, manifest: manifest);
    final expected = checksums[asset.name] ?? asset.sha256;
    if (expected == null || expected.isEmpty) {
      throw AppUpdaterException(
        'Missing SHA256 checksum for ${asset.name}; refusing insecure download',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final destination = File(p.join(tempDir.path, asset.name));
    if (await destination.exists()) {
      await destination.delete();
    }

    final request = http.Request('GET', Uri.parse(asset.downloadUrl));
    final response = await _downloadClient.send(request);
    if (response.statusCode != 200) {
      throw AppUpdaterException(
        'Download failed for ${asset.name} (HTTP ${response.statusCode})',
      );
    }

    final total = response.contentLength ?? asset.sizeBytes ?? 0;
    var received = 0;
    final sink = destination.openWrite();
    try {
      await for (final chunk in response.stream) {
        if (shouldCancel?.call() == true) {
          throw const AppUpdaterException('Download cancelled');
        }
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null) {
          onProgress(received, total > 0 ? total : received);
        }
      }
    } finally {
      await sink.close();
    }

    if (shouldCancel?.call() == true) {
      if (await destination.exists()) {
        await destination.delete();
      }
      throw const AppUpdaterException('Download cancelled');
    }

    await verifyFileSha256(file: destination, expectedHex: expected);
    return destination;
  }

  /// Installs a verified update package using the platform-specific installer.
  Future<void> installDownloadedUpdate(File verifiedPackage) async {
    await UpdatePlatformInstaller.forCurrentPlatform().install(verifiedPackage);
  }

  /// Whether in-app install is blocked by the current packaging (snap/flatpak).
  bool get isInstallBlockedByPackageManager {
    final context = UpdateInstallContext.current();
    return context.isManagedPackage;
  }

  /// Picks the best Release asset for the current packaging context.
  UpdateAsset? platformAssetFor(
    UpdateManifest manifest, {
    UpdateInstallContext? context,
  }) {
    return selectUpdateAsset(
      manifest,
      context ?? UpdateInstallContext.current(),
    );
  }

  Future<Map<String, String>> _resolveChecksums({
    required UpdateAsset asset,
    UpdateManifest? manifest,
  }) async {
    if (manifest != null && manifest.checksums.isNotEmpty) {
      return manifest.checksums;
    }

    final checksumsUrl = manifest?.checksumsUrl ??
        manifest?.assetNamed(kSha256SumsFileName)?.downloadUrl;
    if (checksumsUrl == null || checksumsUrl.isEmpty) {
      if (asset.sha256 != null) {
        return {asset.name: asset.sha256!};
      }
      return const {};
    }

    final text = await _releasesClient.downloadText(checksumsUrl);
    return parseSha256SumsText(text);
  }

  void dispose() {
    _releasesClient.close();
    _downloadClient.close();
  }
}

class AppUpdaterException implements Exception {
  const AppUpdaterException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) return 'AppUpdaterException: $message';
    return 'AppUpdaterException: $message ($cause)';
  }
}
