import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/updater/app_updater_service.dart';
import 'package:querya_desktop/core/updater/github_releases_client.dart';
import 'package:querya_desktop/core/updater/sha256_checksums.dart';
import 'package:querya_desktop/core/updater/update_manifest.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;

  @override
  Future<String?> getTemporaryPath() async => _root;

  @override
  Future<String?> getApplicationDocumentsPath() async => _root;

  @override
  Future<String?> getApplicationCachePath() async => _root;

  @override
  Future<String?> getLibraryPath() async => _root;

  @override
  Future<String?> getExternalStoragePath() async => _root;

  @override
  Future<List<String>?> getExternalCachePaths() async => [_root];

  @override
  Future<List<String>?> getExternalStoragePaths(
          {StorageDirectory? type}) async =>
      [_root];

  @override
  Future<String?> getDownloadsPath() async => _root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_updater_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.updateChannel);
    await LocalDb.instance.deleteAppSetting(
      AppSettingsKeys.checkForUpdatesOnStartup,
    );
  });

  group('parseSha256SumsText', () {
    test('parses sha256sum lines', () {
      const hash =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      const text =
          '$hash  Querya-Desktop-0.5.0-linux.zip\n';
      final parsed = parseSha256SumsText(text);
      expect(parsed['Querya-Desktop-0.5.0-linux.zip'], hash);
    });
  });

  group('AppUpdaterService.checkForUpdates', () {
    test('returns update when GitHub latest is newer', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), kGitHubReleasesLatestUrl);
        return http.Response(
          jsonEncode(_sampleRelease(version: '0.5.0')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AppUpdaterService(
        releasesClient: GitHubReleasesClient(httpClient: client),
        downloadClient: client,
        packageInfoProvider: () async => _packageInfo('0.4.9'),
      );

      final result = await service.checkForUpdates();
      expect(result.currentVersion, '0.4.9');
      expect(result.hasUpdate, isTrue);
      expect(result.availableUpdate?.version, '0.5.0');
      service.dispose();
    });

    test('returns up to date when versions match', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(_sampleRelease(version: '0.4.9')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AppUpdaterService(
        releasesClient: GitHubReleasesClient(httpClient: client),
        downloadClient: client,
        packageInfoProvider: () async => _packageInfo('0.4.9'),
      );

      final result = await service.checkForUpdates();
      expect(result.isUpToDate, isTrue);
      service.dispose();
    });

    test('dev channel uses releases list and accepts pre-release', () async {
      await AppSettings.instance.setUpdateChannel(UpdateChannel.dev);

      final client = MockClient((request) async {
        expect(request.url.toString(), kGitHubReleasesListUrl);
        return http.Response(
          jsonEncode([
            _sampleRelease(version: '0.5.0-beta.1'),
            _sampleRelease(version: '0.4.9'),
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AppUpdaterService(
        releasesClient: GitHubReleasesClient(httpClient: client),
        downloadClient: client,
        packageInfoProvider: () async => _packageInfo('0.4.9'),
      );

      final result = await service.checkForUpdates();
      expect(result.availableUpdate?.version, '0.5.0-beta.1');
      service.dispose();
    });

    test('background mode returns error message instead of throwing', () async {
      final client = MockClient((request) async {
        return http.Response('rate limited', 403);
      });

      final service = AppUpdaterService(
        releasesClient: GitHubReleasesClient(httpClient: client),
        downloadClient: client,
        packageInfoProvider: () async => _packageInfo('0.4.9'),
      );

      final result = await service.checkForUpdates(background: true);
      expect(result.errorMessage, isNotNull);
      service.dispose();
    });
  });

  group('AppUpdaterService.downloadAsset', () {
    test('verifies SHA256 and reports progress', () async {
      final payload = utf8.encode('querya-update-payload');
      final digest = sha256.convert(payload).toString();
      const fileName = 'Querya-Desktop-0.5.0-linux.zip';
      final checksums = '$digest  $fileName\n';

      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('SHA256SUMS.txt')) {
          return http.Response(checksums, 200);
        }
        if (url.contains(fileName)) {
          return http.Response.bytes(payload, 200);
        }
        return http.Response('not found', 404);
      });

      final service = AppUpdaterService(
        releasesClient: GitHubReleasesClient(httpClient: client),
        downloadClient: client,
        packageInfoProvider: () async => _packageInfo('0.4.9'),
      );

      final asset = UpdateAsset(
        name: fileName,
        downloadUrl: 'https://example.com/$fileName',
      );
      final manifest = UpdateManifest(
        version: '0.5.0',
        changelog: '',
        assets: [asset],
        checksumsUrl: 'https://example.com/SHA256SUMS.txt',
      );

      final progress = <List<int>>[];
      final file = await service.downloadAsset(
        asset,
        manifest: manifest,
        onProgress: (received, total) => progress.add([received, total]),
      );

      expect(await file.readAsBytes(), payload);
      expect(progress, isNotEmpty);
      service.dispose();
    });

    test('throws when checksum mismatches', () async {
      final payload = utf8.encode('tampered');
      const fileName = 'Querya-Desktop-0.5.0-linux.zip';
      final checksums =
          '${'a' * 64}  $fileName\n'; // wrong hash on purpose

      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('SHA256SUMS.txt')) {
          return http.Response(checksums, 200);
        }
        return http.Response.bytes(payload, 200);
      });

      final service = AppUpdaterService(
        releasesClient: GitHubReleasesClient(httpClient: client),
        downloadClient: client,
        packageInfoProvider: () async => _packageInfo('0.4.9'),
      );

      final asset = UpdateAsset(
        name: fileName,
        downloadUrl: 'https://example.com/$fileName',
      );
      final manifest = UpdateManifest(
        version: '0.5.0',
        changelog: '',
        assets: [asset],
        checksumsUrl: 'https://example.com/SHA256SUMS.txt',
      );

      expect(
        () => service.downloadAsset(asset, manifest: manifest),
        throwsA(isA<UpdateChecksumMismatchException>()),
      );
      service.dispose();
    });
  });
}

Future<PackageInfo> _packageInfo(String version) async {
  return PackageInfo(
    appName: 'Querya',
    packageName: 'querya_desktop',
    version: version,
    buildNumber: '1',
  );
}

Map<String, dynamic> _sampleRelease({required String version}) {
  return {
    'tag_name': 'v$version',
    'published_at': '2026-07-10T12:00:00Z',
    'body': 'Release notes',
    'assets': [
      {
        'name': 'Querya-Desktop-$version-linux.zip',
        'browser_download_url':
            'https://github.com/example/Querya-Desktop-$version-linux.zip',
        'size': 100,
      },
      {
        'name': 'SHA256SUMS.txt',
        'browser_download_url': 'https://github.com/example/SHA256SUMS.txt',
        'size': 64,
      },
    ],
  };
}
