import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
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

Future<void> _copyFixture(String fixtureName, File destination) async {
  final source = File(p.join('test/fixtures/themes', fixtureName));
  await destination.writeAsString(await source.readAsString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory themesDir;
  late Directory importedDir;
  late ThemeRegistryService registry;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_theme_registry_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
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
    if (await themesDir.exists()) {
      await themesDir.delete(recursive: true);
    }
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ThemeRegistryService.loadThemeDefinitions', () {
    test('preserves marketplace metadata on custom theme scan', () async {
      await _copyFixture(
        'querya_custom_metadata.json',
        File(p.join(themesDir.path, 'querya_custom_metadata.json')),
      );

      final definitions = await registry.loadThemeDefinitions();
      final metadataTheme = definitions.singleWhere(
        (d) => d.id == 'fixture-custom-metadata',
      );

      expect(metadataTheme.metadata, isNotNull);
      expect(metadataTheme.metadata!.author, 'Querya Themes');
      expect(metadataTheme.metadata!.license, 'MIT');
      expect(metadataTheme.metadata!.tags, ['cyberpunk', 'neon', 'dark']);
      expect(metadataTheme.metadata!.pickerSubtitle, 'Querya Themes');
    });

    test('includes valid custom and VS Code themes, skips broken file', () async {
      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );
      await _copyFixture(
        'dark_subset.json',
        File(p.join(themesDir.path, 'dark_subset.json')),
      );
      await _copyFixture(
        'querya_custom_invalid_missing_id.json',
        File(p.join(themesDir.path, 'broken.json')),
      );

      final definitions = await registry.loadThemeDefinitions();

      expect(definitions, hasLength(2));
      expect(
        definitions.map((d) => d.format).toSet(),
        equals({ThemeFormat.queryaCustom, ThemeFormat.vscode}),
      );
      expect(
        definitions.singleWhere((d) => d.format == ThemeFormat.queryaCustom).id,
        'fixture-custom-dark',
      );
      expect(
        definitions.singleWhere((d) => d.format == ThemeFormat.vscode).name,
        'Fixture Dark Subset',
      );
    });

    test('sorts definitions by name case-insensitively', () async {
      await File(p.join(themesDir.path, 'z-theme.json')).writeAsString('''
{
  "schema": "querya.theme.v1",
  "id": "z-theme",
  "name": "Zebra Theme",
  "type": "dark",
  "shadcn_colors": {},
  "editor_colors": {}
}
''');
      await File(p.join(themesDir.path, 'a-theme.json')).writeAsString('''
{
  "schema": "querya.theme.v1",
  "id": "a-theme",
  "name": "alpha theme",
  "type": "light",
  "shadcn_colors": {},
  "editor_colors": {}
}
''');

      final definitions = await registry.loadThemeDefinitions();

      expect(definitions.map((d) => d.name), ['alpha theme', 'Zebra Theme']);
    });

    test('content hash changes when file content changes', () async {
      final themeFile = File(p.join(themesDir.path, 'hash-theme.json'));
      await _copyFixture('querya_custom_minimal.json', themeFile);

      final before = await registry.loadThemeDefinitions();
      expect(before, hasLength(1));
      final originalHash = before.single.contentHash;

      final raw = await themeFile.readAsString();
      await themeFile.writeAsString(raw.replaceFirst('#FF00AA', '#00FFAA'));

      final after = await registry.loadThemeDefinitions();
      expect(after, hasLength(1));
      expect(after.single.contentHash, isNot(originalHash));
    });

    test('scans imported directory with imported source', () async {
      await _copyFixture(
        'querya_custom_light.json',
        File(p.join(importedDir.path, 'querya_custom_light.json')),
      );

      final definitions = await registry.loadThemeDefinitions();

      expect(definitions, hasLength(1));
      expect(definitions.single.source, ThemeSource.imported);
      expect(definitions.single.id, 'fixture-custom-light');
    });

    test('ignores non-json theme extensions', () async {
      await File(p.join(themesDir.path, 'notes.txt')).writeAsString('not a theme');
      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );

      final definitions = await registry.loadThemeDefinitions();

      expect(definitions, hasLength(1));
    });
  });

  group('ThemeRegistryService.loadTheme', () {
    test('loads custom theme successfully', () async {
      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );

      final definition = (await registry.loadThemeDefinitions()).single;
      final result = await registry.loadTheme(definition);

      expect(result, isA<ThemeLoadSuccess>());
      final success = result as ThemeLoadSuccess;
      expect(success.definition, definition);
      expect(success.theme.brightness, Brightness.dark);
      expect(success.theme.colorScheme.primary, parseQueryaThemeColor('#38BDF8'));
    });

    test('loads VS Code theme successfully', () async {
      await _copyFixture(
        'dark_subset.json',
        File(p.join(themesDir.path, 'dark_subset.json')),
      );

      final definition = (await registry.loadThemeDefinitions()).single;
      final result = await registry.loadTheme(definition);

      expect(result, isA<ThemeLoadSuccess>());
      final success = result as ThemeLoadSuccess;
      expect(success.theme.editor.background, parseQueryaThemeColor('#1e1e1e'));
    });

    test('returns failure for deleted file', () async {
      const definition = ThemeDefinition(
        id: 'missing-theme',
        name: 'Missing Theme',
        source: ThemeSource.filesystem,
        format: ThemeFormat.queryaCustom,
        isDark: true,
        path: '/no/such/theme.json',
      );

      final result = await registry.loadTheme(definition);

      expect(result, isA<ThemeLoadFailure>());
      expect((result as ThemeLoadFailure).message, 'Theme file not found.');
    });

    test('returns failure for invalid custom file', () async {
      final file = File(p.join(themesDir.path, 'broken.json'));
      await _copyFixture('querya_custom_invalid_missing_id.json', file);
      final definition = ThemeDefinition(
        id: 'broken',
        name: 'Broken',
        source: ThemeSource.filesystem,
        format: ThemeFormat.queryaCustom,
        isDark: true,
        path: file.path,
      );

      final result = await registry.loadTheme(definition);

      expect(result, isA<ThemeLoadFailure>());
      expect((result as ThemeLoadFailure).message, contains('id'));
    });
  });

  group('ThemeRegistryService.importThemeFile', () {
    test('imports custom theme into user themes directory', () async {
      final source = File(p.join('test/fixtures/themes', 'querya_custom_dark.json'));
      final result = await registry.importThemeFile(source.path);

      expect(result, isA<ThemeDefinitionImportSuccess>());
      final success = result as ThemeDefinitionImportSuccess;
      expect(success.reusedExisting, isFalse);
      expect(success.definition.id, 'fixture-custom-dark');
      expect(success.definition.source, ThemeSource.filesystem);
      expect(
        await File(p.join(themesDir.path, 'fixture-custom-dark.json')).exists(),
        isTrue,
      );

      final definitions = await registry.loadThemeDefinitions();
      expect(
        definitions.map((d) => d.id),
        contains('fixture-custom-dark'),
      );
    });

    test('imports VS Code theme with slugified filename', () async {
      final source = File(p.join('test/fixtures/themes', 'dark_subset.json'));
      final result = await registry.importThemeFile(source.path);

      expect(result, isA<ThemeDefinitionImportSuccess>());
      final success = result as ThemeDefinitionImportSuccess;
      expect(success.definition.format, ThemeFormat.vscode);
      expect(
        p.basename(success.definition.path!),
        'fixture-dark-subset.json',
      );
    });

    test('reuses existing file when content hash matches', () async {
      final source = File(p.join('test/fixtures/themes', 'querya_custom_minimal.json'));
      final first = await registry.importThemeFile(source.path);
      expect(first, isA<ThemeDefinitionImportSuccess>());
      final firstSuccess = first as ThemeDefinitionImportSuccess;

      final second = await registry.importThemeFile(source.path);
      expect(second, isA<ThemeDefinitionImportSuccess>());
      final secondSuccess = second as ThemeDefinitionImportSuccess;
      expect(secondSuccess.reusedExisting, isTrue);
      expect(secondSuccess.definition.path, firstSuccess.definition.path);

      final themeFiles = themesDir
          .listSync()
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.json')
          .length;
      expect(themeFiles, 1);
    });

    test('suffixes custom theme id when same id has different content', () async {
      final source = File(p.join('test/fixtures/themes', 'querya_custom_minimal.json'));
      final first = await registry.importThemeFile(source.path);
      expect(first, isA<ThemeDefinitionImportSuccess>());

      final modified = File(p.join(tempDir.path, 'modified-custom.json'));
      final raw = await source.readAsString();
      await modified.writeAsString(raw.replaceFirst('#FF00AA', '#00FFAA'));

      final second = await registry.importThemeFile(modified.path);
      expect(second, isA<ThemeDefinitionImportSuccess>());
      final secondSuccess = second as ThemeDefinitionImportSuccess;
      expect(secondSuccess.reusedExisting, isFalse);
      expect(secondSuccess.definition.id, 'fixture-custom-minimal-2');

      final definitions = await registry.loadThemeDefinitions();
      expect(
        definitions.map((d) => d.id),
        containsAll(['fixture-custom-minimal', 'fixture-custom-minimal-2']),
      );
    });
  });
}
