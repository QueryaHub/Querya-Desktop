import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_editor_loader.dart';
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

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('querya_theme_editor_loader_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  setUp(() async {
    themesDir = Directory(p.join(tempDir.path, 'themes'));
    await Directory(p.join(themesDir.path, 'imported')).create(recursive: true);
    ThemeController.instance.setRegistryServiceForTest(
      ThemeRegistryService(
        userThemesDirectory: () async => themesDir,
        importedThemesDirectory: () async => Directory(
          p.join(themesDir.path, 'imported'),
        ),
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

  tearDown(() async {
    await ThemeController.instance.stopThemeFolderWatcher();
    await ThemeController.instance.endEditorPreview();
    await AppSettings.instance.clearThemeSettings();
    if (await themesDir.exists()) {
      await themesDir.delete(recursive: true);
    }
    ThemeController.instance.setRegistryServiceForTest(ThemeRegistryService());
    await ThemeController.instance.load();
  });

  group('ThemeEditorLoader', () {
    test('loads custom theme file manifest when available', () async {
      final source =
          File(p.join('test/fixtures/themes', 'querya_custom_dark.json'));
      await File(p.join(themesDir.path, 'querya_custom_dark.json'))
          .writeAsString(await source.readAsString());

      final controller = ThemeController.instance;
      await controller.load();
      await controller.setThemeById('fixture-custom-dark');

      final draft = await ThemeEditorLoader.fromController(controller);
      expect(draft.id, 'fixture-custom-dark');
      expect(draft.shadcnColors['primary'], '#38BDF8');
      expect(draft.editorColors['background'], '#0F1117');
    });
  });

  group('ThemeController editor preview', () {
    test('previewEditorManifest updates active theme and restores', () async {
      final c = ThemeController.instance;
      await c.load();
      final beforePrimary = c.activeTheme.colorScheme.primary;

      final manifest = QueryaThemeManifest.fromJsonString('''
{
  "schema": "querya.theme.v1",
  "id": "preview-test",
  "name": "Preview Test",
  "type": "dark",
  "shadcn_colors": { "primary": "#FF00AA" },
  "editor_colors": { "background": "#010203" }
}
''');

      await c.previewEditorManifest(manifest);
      expect(c.isEditorPreviewActive, isTrue);
      expect(
          c.activeTheme.colorScheme.primary, parseQueryaThemeColor('#FF00AA'));

      await c.endEditorPreview();
      expect(c.isEditorPreviewActive, isFalse);
      expect(c.activeTheme.colorScheme.primary, beforePrimary);
    });
  });
}
