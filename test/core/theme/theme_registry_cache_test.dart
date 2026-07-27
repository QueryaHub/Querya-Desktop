import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/theme/theme_load_result.dart';
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
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
    tempDir = await Directory.systemTemp.createTemp('querya_theme_cache_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  setUp(() async {
    themesDir = Directory(p.join(tempDir.path, 'themes'));
    importedDir = Directory(p.join(themesDir.path, 'imported'));
    await importedDir.create(recursive: true);

    final extDir = Directory(p.join(tempDir.path, 'extensions'));
    ExtensionPaths.mockExtensionsDirectory = extDir;
    if (await extDir.exists()) {
      await extDir.delete(recursive: true);
    }
    await extDir.create(recursive: true);
    await LocalExtensionRegistry.instance.reload();

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
    final extDir = ExtensionPaths.mockExtensionsDirectory;
    if (extDir != null && await extDir.exists()) {
      await extDir.delete(recursive: true);
    }
    ExtensionPaths.mockExtensionsDirectory = null;
    await LocalExtensionRegistry.instance.reload();
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ThemeRegistryService cache', () {
    test('skips theme file read when mtime unchanged on refresh', () async {
      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );

      final first = await registry.loadThemeDefinitions();
      expect(first, hasLength(1));
      final readsAfterCold = registry.themeFileReadCount;
      expect(readsAfterCold, greaterThan(0));

      final second = await registry.loadThemeDefinitions(
        reloadExtensions: false,
      );
      expect(second, hasLength(1));
      expect(second.single.id, first.single.id);
      expect(registry.themeFileReadCount, readsAfterCold);
    });

    test('loads same definition twice with a single parse', () async {
      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );

      final definition = (await registry.loadThemeDefinitions()).single;

      final first = await registry.loadTheme(definition);
      final second = await registry.loadTheme(definition);

      expect(first, isA<ThemeLoadSuccess>());
      expect(second, isA<ThemeLoadSuccess>());
      expect(registry.themeParseCount, 1);
    });

    test('re-parses when content hash changes', () async {
      final themeFile = File(p.join(themesDir.path, 'hash-theme.json'));
      await _copyFixture('querya_custom_minimal.json', themeFile);

      final before = (await registry.loadThemeDefinitions()).single;
      await registry.loadTheme(before);
      expect(registry.themeParseCount, 1);

      final extFile = File(before.path!);
      final raw = await extFile.readAsString();
      await extFile.writeAsString(raw.replaceFirst('#FF00AA', '#00FFAA'));

      final after = (await registry.loadThemeDefinitions()).single;
      expect(after.contentHash, isNot(before.contentHash));

      await registry.loadTheme(after);
      expect(registry.themeParseCount, 2);
    });

    test('evicts oldest entry after cache limit', () async {
      final limitedRegistry = ThemeRegistryService(
        maxCacheEntries: 2,
        userThemesDirectory: () async => themesDir,
        importedThemesDirectory: () async => importedDir,
        bundledThemeAssetFiles: const [],
      );

      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );
      await _copyFixture(
        'querya_custom_light.json',
        File(p.join(themesDir.path, 'querya_custom_light.json')),
      );
      await _copyFixture(
        'querya_custom_minimal.json',
        File(p.join(themesDir.path, 'querya_custom_minimal.json')),
      );

      final definitions = await limitedRegistry.loadThemeDefinitions();
      expect(definitions, hasLength(3));

      for (final definition in definitions) {
        await limitedRegistry.loadTheme(definition);
      }
      expect(limitedRegistry.themeParseCount, 3);

      await limitedRegistry.loadTheme(definitions.first);
      expect(limitedRegistry.themeParseCount, 4);
    });

    test('clearCache forces re-parse on next load', () async {
      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );

      final definition = (await registry.loadThemeDefinitions()).single;
      await registry.loadTheme(definition);
      await registry.loadTheme(definition);
      expect(registry.themeParseCount, 1);

      registry.clearCache();
      await registry.loadTheme(definition);
      await registry.loadTheme(definition);
      expect(registry.themeParseCount, 1);
    });
  });
}
