import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
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

    final extDir = Directory(p.join(tempDir.path, 'extensions'));
    ExtensionPaths.mockExtensionsDirectory = extDir;
    if (await extDir.exists()) {
      await extDir.delete(recursive: true);
    }
    await extDir.create(recursive: true);
    await LocalExtensionRegistry.instance.reload();

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
    final extDir = ExtensionPaths.mockExtensionsDirectory;
    if (extDir != null && await extDir.exists()) {
      await extDir.delete(recursive: true);
    }
    ExtensionPaths.mockExtensionsDirectory = null;
    await LocalExtensionRegistry.instance.reload();
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
        await File(p.join(tempDir.path, 'extensions', 'fixture-custom-dark', 'theme.json')).exists(),
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
      expect(await ExtensionPaths.mockExtensionsDirectory!.list().length, 0);
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
      final extDir = ExtensionPaths.mockExtensionsDirectory!;
      final themeExt = Directory(p.join(extDir.path, 'fixture-custom-dark'));
      await themeExt.create(recursive: true);
      await File(p.join(themeExt.path, 'theme.json')).writeAsString(raw);
      await File(p.join(themeExt.path, 'manifest.json')).writeAsString('''{
        "schema": "querya.extension.v1",
        "id": "fixture-custom-dark",
        "name": "Fixture Custom Dark",
        "version": "1.0.0",
        "publisher": "Unknown",
        "type": "theme",
        "main": "theme.json"
      }''');
      await LocalExtensionRegistry.instance.reload();

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
