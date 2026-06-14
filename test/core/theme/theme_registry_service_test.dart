import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/theme/theme_definition.dart';
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
}
