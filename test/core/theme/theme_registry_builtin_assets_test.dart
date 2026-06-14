import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/theme/builtin_theme_assets.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/theme_definition.dart';
import 'package:querya_desktop/core/theme/theme_load_result.dart';
import 'package:querya_desktop/core/theme/theme_registry_service.dart';

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
  late Directory importedDir;
  late ThemeRegistryService registry;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('querya_builtin_theme_assets_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  setUp(() async {
    themesDir = Directory(p.join(tempDir.path, 'themes'));
    importedDir = Directory(p.join(themesDir.path, 'imported'));
    await importedDir.create(recursive: true);

    registry = ThemeRegistryService(
      userThemesDirectory: () async => themesDir,
      importedThemesDirectory: () async => importedDir,
      assetLoader: _fixtureAssetLoader,
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

  group('ThemeRegistryService built-in asset themes', () {
    test('includes bundled cyberpunk-neon definition without filesystem scan',
        () async {
      final definitions = await registry.loadThemeDefinitions();

      expect(definitions, hasLength(1));
      final cyberpunk = definitions.single;
      expect(cyberpunk.id, 'cyberpunk-neon');
      expect(cyberpunk.name, 'Querya Cyberpunk Neon');
      expect(cyberpunk.source, ThemeSource.builtin);
      expect(cyberpunk.format, ThemeFormat.vscode);
      expect(cyberpunk.isDark, isTrue);
      expect(cyberpunk.isFileBacked, isFalse);
      expect(
        cyberpunk.path,
        BuiltinThemeAssets.assetPath('cyberpunk-neon.json'),
      );
      expect(cyberpunk.contentHash, isNotEmpty);
    });

    test('loads built-in asset theme from bundle', () async {
      final definition = (await registry.loadThemeDefinitions()).single;
      final result = await registry.loadTheme(definition);

      expect(result, isA<ThemeLoadSuccess>());
      final success = result as ThemeLoadSuccess;
      expect(success.theme.brightness, Brightness.dark);
      expect(
        success.theme.editor.background,
        parseQueryaThemeColor('#0a0a14'),
      );
    });

    test('sorts built-in assets with filesystem themes by name', () async {
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

      final definitions = await registry.loadThemeDefinitions();

      expect(definitions.map((d) => d.name), [
        'Querya Cyberpunk Neon',
        'Zebra Theme',
      ]);
    });
  });
}
