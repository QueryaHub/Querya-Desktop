import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
import 'package:querya_desktop/core/theme/theme_registry_service.dart';
import 'package:querya_desktop/core/theme/theme_remote_install_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;
}

Future<String> _fixtureAssetLoader(String assetPath) async {
  final fileName = p.basename(assetPath);
  return File(p.join('test/fixtures/themes', fileName)).readAsString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory themesDir;
  late ThemeRegistryService registry;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('querya_theme_remote_install_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  setUp(() async {
    themesDir = Directory(p.join(tempDir.path, 'themes'));
    await Directory(p.join(themesDir.path, 'imported')).create(recursive: true);
    registry = ThemeRegistryService(
      userThemesDirectory: () async => themesDir,
      importedThemesDirectory: () async => Directory(
        p.join(themesDir.path, 'imported'),
      ),
      assetLoader: _fixtureAssetLoader,
    );
    ThemeController.instance.setRegistryServiceForTest(registry);
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    await ThemeController.instance.stopThemeFolderWatcher();
    await ThemeController.instance.endEditorPreview();
    await AppSettings.instance.clearThemeSettings();
    if (await themesDir.exists()) {
      await themesDir.delete(recursive: true);
    }
    ThemeController.instance.setRegistryServiceForTest(ThemeRegistryService());
  });

  group('ThemeRemoteInstallService', () {
    test('installs valid HTTPS theme content', () async {
      final raw = await File('test/fixtures/themes/querya_custom_dark.json')
          .readAsString();
      final service = ThemeRemoteInstallService(
        registry,
        allowLocalhostInDebug: false,
        httpGet: (_) async => RemoteThemeHttpResponse(
          statusCode: 200,
          body: raw,
        ),
      );

      final result = await service.installFromUrl(
        'https://cdn.example.com/themes/querya_custom_dark.json',
      );

      expect(result, isA<ThemeDefinitionImportSuccess>());
      final success = result as ThemeDefinitionImportSuccess;
      expect(success.definition.id, 'fixture-custom-dark');
      expect(
        await File(p.join(themesDir.path, 'fixture-custom-dark.json')).exists(),
        isTrue,
      );
    });

    test('rejects checksum mismatch and does not write theme file', () async {
      final raw = await File('test/fixtures/themes/querya_custom_dark.json')
          .readAsString();
      final service = ThemeRemoteInstallService(
        registry,
        allowLocalhostInDebug: false,
        httpGet: (_) async => RemoteThemeHttpResponse(
          statusCode: 200,
          body: raw,
        ),
      );

      final result = await service.installFromUrl(
        'https://cdn.example.com/themes/querya_custom_dark.json',
        sha256Checksum: 'deadbeef',
      );

      expect(result, isA<ThemeDefinitionImportFailure>());
      expect(
        (result as ThemeDefinitionImportFailure).message,
        contains('Checksum mismatch'),
      );
      expect(await themesDir.list().length, 1);
    });

    test('rejects invalid JSON without writing to themes folder', () async {
      final service = ThemeRemoteInstallService(
        registry,
        allowLocalhostInDebug: false,
        httpGet: (_) async => const RemoteThemeHttpResponse(
          statusCode: 200,
          body: '{ not valid json',
        ),
      );

      final result = await service.installFromUrl(
        'https://cdn.example.com/themes/broken.json',
      );

      expect(result, isA<ThemeDefinitionImportFailure>());
      final jsonFiles = await themesDir
          .list()
          .where((entity) => entity.path.endsWith('.json'))
          .toList();
      expect(jsonFiles, isEmpty);
    });

    test('rejects non-https URLs', () async {
      final service = ThemeRemoteInstallService(registry);
      final result = await service.installFromUrl('http://example.com/a.json');
      expect(result, isA<ThemeDefinitionImportFailure>());
    });

    test('reuses existing file when remote content hash matches', () async {
      final raw = await File('test/fixtures/themes/querya_custom_dark.json')
          .readAsString();
      await File(p.join(themesDir.path, 'fixture-custom-dark.json'))
          .writeAsString(raw);

      final service = ThemeRemoteInstallService(
        registry,
        allowLocalhostInDebug: false,
        httpGet: (_) async => RemoteThemeHttpResponse(
          statusCode: 200,
          body: raw,
        ),
      );

      final result = await service.installFromUrl(
        'https://cdn.example.com/themes/querya_custom_dark.json',
      );

      expect(result, isA<ThemeDefinitionImportSuccess>());
      expect((result as ThemeDefinitionImportSuccess).reusedExisting, isTrue);
    });
  });

  group('ThemeController remote install', () {
    test('importRegistryThemeFromUrl activates imported theme', () async {
      final raw = await File('test/fixtures/themes/querya_custom_dark.json')
          .readAsString();
      final controller = ThemeController.instance;
      await controller.load();

      final result = await controller.importRegistryThemeFromUrl(
        'https://cdn.example.com/themes/querya_custom_dark.json',
        remoteInstallService: ThemeRemoteInstallService(
          registry,
          allowLocalhostInDebug: false,
          httpGet: (_) async => RemoteThemeHttpResponse(
            statusCode: 200,
            body: raw,
          ),
        ),
      );

      expect(result, isA<ThemeDefinitionImportSuccess>());
      expect(controller.selectedThemeId, 'fixture-custom-dark');
      expect(
        controller.activeTheme.colorScheme.primary,
        parseQueryaThemeColor('#38BDF8'),
      );
    });
  });
}
