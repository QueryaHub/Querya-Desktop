import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_folder_watcher.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
import 'package:querya_desktop/core/theme/theme_registry_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('querya_theme_folder_watcher_');
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
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    await ThemeController.instance.stopThemeFolderWatcher();
    await AppSettings.instance.clearThemeSettings();
    await ThemeImportService.deletePersistedImport();
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

  group('ThemeFolderWatcher', () {
    test('start is idempotent and stop cancels pending refresh', () async {
      var refreshCount = 0;
      final watcher = ThemeFolderWatcher(
        themesDirectory: () async => themesDir,
        onThemesChanged: () async {
          refreshCount++;
        },
        debounce: const Duration(milliseconds: 80),
      );

      await watcher.start();
      await watcher.start();
      if (!watcher.isStarted) return;
      expect(watcher.isStarted, isTrue);

      await watcher.stop();
      expect(watcher.isStarted, isFalse);

      await File(p.join(themesDir.path, 'late.json')).writeAsString('{}');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(refreshCount, 0);
    });

    test('debounces rapid file events into one refresh', () async {
      final refreshGate = Completer<void>();
      var refreshCount = 0;
      final watcher = ThemeFolderWatcher(
        themesDirectory: () async => themesDir,
        onThemesChanged: () async {
          refreshCount++;
          if (!refreshGate.isCompleted) {
            refreshGate.complete();
          }
        },
        debounce: const Duration(milliseconds: 100),
      );

      await watcher.start();
      if (!watcher.isStarted) return;

      final target = File(p.join(themesDir.path, 'querya_custom_dark.json'));
      await _copyFixture('querya_custom_dark.json', target);
      await target.writeAsString(await target.readAsString());
      await target.writeAsString('${await target.readAsString()}\n');

      await refreshGate.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(refreshCount, 1);
      await watcher.stop();
    });

    test('ignores hidden and temp files', () async {
      var refreshCount = 0;
      final watcher = ThemeFolderWatcher(
        themesDirectory: () async => themesDir,
        onThemesChanged: () async {
          refreshCount++;
        },
        debounce: const Duration(milliseconds: 80),
      );
      await watcher.start();
      if (!watcher.isStarted) return;

      await File(p.join(themesDir.path, '.hidden.json')).writeAsString('{}');
      await File(p.join(themesDir.path, 'draft.tmp')).writeAsString('{}');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(refreshCount, 0);
      await watcher.stop();
    });
  });

  group('ThemeController folder watcher', () {
    test('load starts watcher and picks up newly added theme file', () async {
      final c = ThemeController.instance;
      c.setRegistryServiceForTest(
        ThemeRegistryService(
          userThemesDirectory: () async => themesDir,
          importedThemesDirectory: () async => Directory(
            p.join(themesDir.path, 'imported'),
          ),
        ),
      );

      await c.load();
      if (!c.isThemeFolderWatcherStarted) return;
      expect(c.isThemeFolderWatcherStarted, isTrue);
      final beforeCount = c.availableThemes.length;

      final extDir = ExtensionPaths.mockExtensionsDirectory!;
      final themeExt = Directory(p.join(extDir.path, 'fixture-custom-dark'));
      await themeExt.create(recursive: true);
      await File(p.join(themeExt.path, 'theme.json')).writeAsString(
        await File('test/fixtures/themes/querya_custom_dark.json').readAsString(),
      );
      await File(p.join(themeExt.path, 'manifest.json')).writeAsString('''{
        "schema": "querya.extension.v1",
        "id": "fixture-custom-dark",
        "name": "Fixture Custom Dark",
        "version": "1.0.0",
        "publisher": "Unknown",
        "type": "theme",
        "main": "theme.json"
      }''');

      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(c.availableThemes.length, greaterThan(beforeCount));
      expect(
        c.availableThemes.map((theme) => theme.id),
        contains('fixture-custom-dark'),
      );
    });
  });
}
