import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme_preset.dart';

import 'package:querya_desktop/core/theme/theme_definition.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
import 'package:querya_desktop/core/theme/theme_load_result.dart';
import 'package:querya_desktop/core/theme/theme_registry_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory themesDir;
  late Directory importedDir;
  late ThemeRegistryService registry;

  setUpAll(() async {
    tempDir = await Directory.systemTemp
        .createTemp('querya_theme_legacy_import_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  setUp(() async {
    themesDir = Directory(p.join(tempDir.path, 'themes'));
    importedDir = Directory(p.join(themesDir.path, 'imported'));
    await importedDir.create(recursive: true);

    registry = ThemeRegistryService(
      userThemesDirectory: () async => themesDir,
      importedThemesDirectory: () async => importedDir,
      bundledThemeAssetFiles: const [],
    );
  });

  tearDown(() async {
    await AppSettings.instance.clearThemeSettings();
    await ThemeImportService.deletePersistedImport();
    if (await themesDir.exists()) {
      await themesDir.delete(recursive: true);
    }
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ThemeRegistryService legacy imported migration', () {
    test('exposes legacy imported theme from persisted import settings',
        () async {
      final fixture = File('test/fixtures/themes/dark_subset.json');
      final raw = await fixture.readAsString();
      final storedFile = await ThemeImportService.persistedImportFile();
      await storedFile.parent.create(recursive: true);
      await storedFile.writeAsString(raw);

      await AppSettings.instance.setThemeImportedColors({
        'editor.background': '#1e1e1e',
      });
      await AppSettings.instance.setThemeImportName('Fixture Dark Subset');
      await AppSettings.instance.setThemeImportPath(storedFile.path);
      await AppSettings.instance.setThemePreset(QueryaThemePreset.imported);

      final definitions = await registry.loadThemeDefinitions();
      final legacy = definitions.singleWhere(
        (definition) => definition.source == ThemeSource.legacyImported,
      );

      expect(legacy.id, ThemeImportService.legacyImportedThemeId);
      expect(legacy.name, 'Fixture Dark Subset');
      expect(legacy.format, ThemeFormat.vscode);
      expect(legacy.path, storedFile.path);
      expect(
        definitions.where((definition) => definition.id == 'imported'),
        hasLength(1),
      );
    });

    test('loads legacy imported theme definition', () async {
      final fixture = File('test/fixtures/themes/dark_subset.json');
      final raw = await fixture.readAsString();
      final storedFile = await ThemeImportService.persistedImportFile();
      await storedFile.parent.create(recursive: true);
      await storedFile.writeAsString(raw);

      await AppSettings.instance.setThemeImportedColors({
        'editor.background': '#1e1e1e',
      });
      await AppSettings.instance.setThemeImportName('Fixture Dark Subset');
      await AppSettings.instance.setThemeImportPath(storedFile.path);

      final legacy = (await registry.loadThemeDefinitions()).singleWhere(
        (definition) => definition.source == ThemeSource.legacyImported,
      );
      final result = await registry.loadTheme(legacy);

      expect(result, isA<ThemeLoadSuccess>());
      expect(
        (result as ThemeLoadSuccess).theme.workbench.editorBackground,
        const Color(0xFF1E1E1E),
      );
    });

    test('missing legacy file does not crash scan or load', () async {
      await AppSettings.instance.setThemeImportedColors({
        'editor.background': '#1e1e1e',
      });
      await AppSettings.instance.setThemeImportName('Missing Legacy');
      await AppSettings.instance.setThemeImportPath(
        p.join(themesDir.path, 'missing-imported.json'),
      );

      final definitions = await registry.loadThemeDefinitions();
      final legacy = definitions.singleWhere(
        (definition) => definition.source == ThemeSource.legacyImported,
      );

      expect(legacy.name, 'Missing Legacy');
      final result = await registry.loadTheme(legacy);
      expect(result, isA<ThemeLoadFailure>());
      expect((result as ThemeLoadFailure).message, 'Theme file not found.');
    });


  });
}
