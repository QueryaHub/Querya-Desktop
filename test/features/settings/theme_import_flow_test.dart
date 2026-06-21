import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_definition.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/theme/theme_registry_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;

  @override
  Future<String?> getTemporaryPath() async => _root;

  @override
  Future<String?> getApplicationDocumentsPath() async => _root;
}

Future<String> _fixtureAssetLoader(String assetPath) async {
  final fileName = p.basename(assetPath);
  return File(p.join('test/fixtures/themes', fileName)).readAsString();
}

Future<File> _stageFixtureSource(
  Directory tempDir,
  String fixtureName,
  String sourceName,
) async {
  final source = File(p.join(tempDir.path, sourceName));
  final fixture = File(p.join('test/fixtures/themes', fixtureName));
  await source.writeAsString(await fixture.readAsString());
  return source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory themesDir;
  late Directory importedDir;
  late ThemeRegistryService registry;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('querya_theme_import_flow_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  setUp(() async {
    themesDir = Directory(p.join(tempDir.path, 'themes'));
    importedDir = Directory(p.join(themesDir.path, 'imported'));
    await importedDir.create(recursive: true);

    final extensionsDir = Directory(p.join(tempDir.path, 'extensions'));
    ExtensionPaths.mockExtensionsDirectory = extensionsDir;
    await LocalExtensionRegistry.instance.reload();

    registry = ThemeRegistryService(
      userThemesDirectory: () async => themesDir,
      importedThemesDirectory: () async => importedDir,
      assetLoader: _fixtureAssetLoader,
    );
    ThemeController.instance.setRegistryServiceForTest(registry);
    await ThemeController.instance.load();
  });

  tearDown(() async {
    await AppSettings.instance.clearThemeSettings();
    await ThemeImportService.deletePersistedImport();
    if (await themesDir.exists()) {
      await themesDir.delete(recursive: true);
    }
    ExtensionPaths.mockExtensionsDirectory = null;
    await LocalExtensionRegistry.instance.reload();
    ThemeController.instance.setRegistryServiceForTest(
      ThemeRegistryService(
        userThemesDirectory: () async => themesDir,
        importedThemesDirectory: () async => importedDir,
        assetLoader: _fixtureAssetLoader,
      ),
    );
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('theme import flow', () {
    test('imports custom JSON, applies theme, and restores after reload',
        () async {
      final c = ThemeController.instance;
      final source = await _stageFixtureSource(
        tempDir,
        'querya_custom_dark.json',
        'incoming-custom-dark.json',
      );

      final importResult = await c.importRegistryThemeFile(source.path);

      expect(importResult, isA<ThemeDefinitionImportSuccess>());
      final success = importResult as ThemeDefinitionImportSuccess;
      expect(success.definition.id, 'fixture-custom-dark');
      expect(success.definition.source, ThemeSource.filesystem);
      expect(
        c.availableThemes.map((theme) => theme.id),
        contains('fixture-custom-dark'),
      );
      expect(c.selectedThemeId, 'fixture-custom-dark');
      expect(c.selectedThemeLoadError, isNull);
      expect(
        c.activeTheme.colorScheme.primary,
        parseQueryaThemeColor('#38BDF8'),
      );
      expect(
        await File(p.join(tempDir.path, 'extensions', 'fixture-custom-dark', 'theme.json')).exists(),
        isTrue,
      );
      expect(await AppSettings.instance.getSelectedThemeId(),
          'fixture-custom-dark');
      expect(
        await AppSettings.instance.getSelectedThemeSource(),
        'filesystem',
      );

      await c.load();

      expect(c.selectedThemeId, 'fixture-custom-dark');
      expect(c.selectedThemeLoadError, isNull);
      expect(
        c.activeTheme.colorScheme.primary,
        parseQueryaThemeColor('#38BDF8'),
      );
      expect(
        c.activeTheme.editor.background,
        parseQueryaThemeColor('#0F1117'),
      );
    });

    test('imports VS Code JSON through registry and restores after reload',
        () async {
      final c = ThemeController.instance;
      final source = await _stageFixtureSource(
        tempDir,
        'dark_subset.json',
        'incoming-vscode-dark.json',
      );

      final importResult = await c.importRegistryThemeFile(source.path);

      expect(importResult, isA<ThemeDefinitionImportSuccess>());
      final success = importResult as ThemeDefinitionImportSuccess;
      expect(success.definition.format, ThemeFormat.vscode);
      expect(c.selectedThemeId, 'fixture-dark-subset');
      expect(
        c.activeTheme.editor.background,
        parseQueryaThemeColor('#1e1e1e'),
      );

      await c.load();

      expect(c.selectedThemeId, 'fixture-dark-subset');
      expect(c.selectedThemeLoadError, isNull);
      expect(
        c.activeTheme.editor.background,
        parseQueryaThemeColor('#1e1e1e'),
      );
    });
  });
}
