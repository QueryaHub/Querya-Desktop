import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_preset.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
import 'package:querya_desktop/core/theme/theme_load_result.dart';
import 'package:querya_desktop/core/theme/theme_definition.dart';
import 'package:querya_desktop/core/theme/theme_registry_service.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

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

Future<void> _copyFixture(String fixtureName, File destination) async {
  final source = File(p.join('test/fixtures/themes', fixtureName));
  await destination.writeAsString(await source.readAsString());
}

class _GatedRegistryService extends ThemeRegistryService {
  _GatedRegistryService({
    required super.userThemesDirectory,
    required super.importedThemesDirectory,
  });

  final gate = Completer<void>();

  @override
  Future<List<ThemeDefinition>> loadThemeDefinitions() async {
    await gate.future;
    return super.loadThemeDefinitions();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory themesDir;
  late Directory importedDir;
  late ThemeRegistryService registry;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('querya_theme_controller_test_');
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
    await AppSettings.instance.clearThemeSettings();
    await ThemeImportService.deletePersistedImport();
    if (await themesDir.exists()) {
      await themesDir.delete(recursive: true);
    }
    ThemeController.instance.setRegistryServiceForTest(ThemeRegistryService());
    await ThemeController.instance.load();
  });

  test('load defaults to dark preset', () async {
    final c = ThemeController.instance;
    await c.load();
    expect(c.themeMode, ThemeMode.dark);
    expect(c.preset, QueryaThemePreset.queryaDark);
    expect(c.activeTheme, QueryaTheme.darkDefault);
    expect(c.isLoaded, isTrue);
    expect(c.availableThemes.map((theme) => theme.id), containsAll([
      ThemeController.builtinQueryaDarkId,
      ThemeController.builtinQueryaLightId,
    ]));
    expect(c.effectiveSelectedThemeId, ThemeController.builtinQueryaDarkId);
  });

  test('setThemeMode light persists and updates activeTheme', () async {
    final c = ThemeController.instance;
    await c.load();
    await c.setThemeMode(ThemeMode.light);
    expect(c.activeTheme, QueryaTheme.lightDefault);
    expect(await AppSettings.instance.getThemeMode(), ThemeMode.light);
    expect(
      await AppSettings.instance.getThemePreset(),
      QueryaThemePreset.queryaLight,
    );
  });

  test('resetToDefaults restores dark', () async {
    final c = ThemeController.instance;
    await c.setThemeMode(ThemeMode.light);
    await c.resetToDefaults();
    expect(c.themeMode, ThemeMode.dark);
    expect(c.activeTheme, QueryaTheme.darkDefault);
  });

  test('setWorkbenchColor overrides sidebar and persists', () async {
    final c = ThemeController.instance;
    await c.load();
    await c.setWorkbenchColor(
      'sideBar.background',
      const Color(0xFFFF0000),
    );
    expect(
      c.activeTheme.workbench.sidebarBackground,
      const Color(0xFFFF0000),
    );
    expect(
      (await AppSettings.instance.getThemeColorOverrides())['sideBar.background'],
      '#ff0000',
    );

    await c.clearColorOverrides();
    expect(c.userColorOverrides, isEmpty);
    expect(
      c.activeTheme.workbench.sidebarBackground,
      QueryaTheme.darkDefault.workbench.sidebarBackground,
    );
  });

  test('importThemeFromFile applies imported colors to activeTheme', () async {
    final c = ThemeController.instance;
    await c.load();
    final fixture = File('test/fixtures/themes/dark_subset.json');
    final result = await c.importThemeFromFile(fixture.path);
    expect(result, isA<ThemeImportSuccess>());
    expect(c.preset, QueryaThemePreset.imported);
    expect(c.hasImportedTheme, isTrue);
    expect(
      c.activeTheme.workbench.editorBackground,
      const Color(0xFF1E1E1E),
    );
    await c.resetToDefaults();
    expect(c.preset, QueryaThemePreset.queryaDark);
  });

  test('setThemeAnimationEnabled persists and reset clears', () async {
    final c = ThemeController.instance;
    await c.load();
    expect(c.themeAnimationEnabled, isFalse);

    await c.setThemeAnimationEnabled(true);
    expect(c.themeAnimationEnabled, isTrue);
    expect(await AppSettings.instance.getThemeAnimationEnabled(), isTrue);

    await c.resetToDefaults();
    expect(c.themeAnimationEnabled, isFalse);
    expect(await AppSettings.instance.getThemeAnimationEnabled(), isFalse);
  });

  test('clearColorOverrides does not reset theme mode', () async {
    final c = ThemeController.instance;
    await c.setThemeMode(ThemeMode.light);
    await c.setWorkbenchColor('editor.background', const Color(0xFF111111));
    await c.clearColorOverrides();
    expect(c.themeMode, ThemeMode.light);
    expect(c.activeTheme, QueryaTheme.lightDefault);
  });

  group('registry integration', () {
    test('setThemeById applies registry theme and persists selection', () async {
      final c = ThemeController.instance;
      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );
      await c.load();

      await c.setThemeById('fixture-custom-dark');

      expect(c.selectedThemeId, 'fixture-custom-dark');
      expect(c.selectedThemeLoadError, isNull);
      expect(c.activeTheme.colorScheme.primary, parseQueryaThemeColor('#38BDF8'));
      expect(await AppSettings.instance.getSelectedThemeId(), 'fixture-custom-dark');
      expect(
        await AppSettings.instance.getSelectedThemeSource(),
        'filesystem',
      );
    });

    test('previewThemeById does not change activeTheme', () async {
      final c = ThemeController.instance;
      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );
      await c.load();

      final before = c.activeTheme;
      final preview = await c.previewThemeById('fixture-custom-dark');

      expect(preview, isA<ThemeLoadSuccess>());
      expect(c.activeTheme, same(before));
      expect(c.selectedThemeId, isNull);
    });

    test('broken selected id falls back to Querya Dark without clearing settings',
        () async {
      final c = ThemeController.instance;
      await AppSettings.instance.setSelectedThemeId('missing-theme');
      await AppSettings.instance.setSelectedThemeSource('filesystem');
      await AppSettings.instance.setSelectedThemePath('/tmp/missing-theme.json');
      await AppSettings.instance.setThemePreset(QueryaThemePreset.queryaLight);

      await c.load();

      expect(c.activeTheme, QueryaTheme.darkDefault);
      expect(c.selectedThemeLoadError, isNotNull);
      expect(await AppSettings.instance.getSelectedThemeId(), 'missing-theme');
      expect(
        await AppSettings.instance.getThemePreset(),
        QueryaThemePreset.queryaLight,
      );
    });

    test('setPreset clears registry selection', () async {
      final c = ThemeController.instance;
      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );
      await c.load();
      await c.setThemeById('fixture-custom-dark');
      expect(c.selectedThemeId, 'fixture-custom-dark');

      await c.setPreset(QueryaThemePreset.queryaLight);

      expect(c.selectedThemeId, isNull);
      expect(c.activeTheme, QueryaTheme.lightDefault);
      expect(await AppSettings.instance.getSelectedThemeId(), isNull);
    });

    test('setThemeById applies built-in Querya Light preset', () async {
      final c = ThemeController.instance;
      await c.load();

      await c.setThemeById(ThemeController.builtinQueryaLightId);

      expect(c.preset, QueryaThemePreset.queryaLight);
      expect(c.selectedThemeId, isNull);
      expect(c.effectiveSelectedThemeId, ThemeController.builtinQueryaLightId);
      expect(c.activeTheme, QueryaTheme.lightDefault);
      expect(await AppSettings.instance.getSelectedThemeId(), isNull);
    });

    test('previewThemeById returns built-in theme without registry file',
        () async {
      final c = ThemeController.instance;
      await c.load();

      final result = await c.previewThemeById(ThemeController.builtinQueryaDarkId);

      expect(result, isA<ThemeLoadSuccess>());
      expect((result as ThemeLoadSuccess).theme, QueryaTheme.darkDefault);
    });

    test('resetToDefaults keeps built-in themes in picker list', () async {
      final c = ThemeController.instance;
      await c.load();
      await c.setThemeMode(ThemeMode.light);
      await c.resetToDefaults();

      expect(c.availableThemes.map((theme) => theme.id), containsAll([
        ThemeController.builtinQueryaDarkId,
        ThemeController.builtinQueryaLightId,
      ]));
      expect(c.effectiveSelectedThemeId, ThemeController.builtinQueryaDarkId);
    });
  });

  group('loadAvailableThemes', () {
    test('picks up newly added filesystem theme', () async {
      final c = ThemeController.instance;
      await c.load();
      final beforeCount = c.availableThemes.length;

      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );
      await c.loadAvailableThemes();

      expect(c.availableThemes.length, greaterThan(beforeCount));
      expect(
        c.availableThemes.map((theme) => theme.id),
        contains('fixture-custom-dark'),
      );
      expect(c.isLoadingAvailableThemes, isFalse);
    });

    test('preserves active registry theme without reloading from disk',
        () async {
      final c = ThemeController.instance;
      await _copyFixture(
        'querya_custom_dark.json',
        File(p.join(themesDir.path, 'querya_custom_dark.json')),
      );
      await c.load();
      await c.setThemeById('fixture-custom-dark');
      final before = c.activeTheme;

      await File(p.join(themesDir.path, 'querya_custom_dark.json'))
          .writeAsString('not valid theme json');

      await c.loadAvailableThemes();

      expect(c.activeTheme, same(before));
      expect(c.selectedThemeId, 'fixture-custom-dark');
    });

    test('sets isLoadingAvailableThemes while refresh is in progress', () async {
      final c = ThemeController.instance;
      await c.load();

      final gated = _GatedRegistryService(
        userThemesDirectory: () async => themesDir,
        importedThemesDirectory: () async => importedDir,
      );
      c.setRegistryServiceForTest(gated);

      final refresh = c.loadAvailableThemes();
      expect(c.isLoadingAvailableThemes, isTrue);

      gated.gate.complete();
      await refresh;

      expect(c.isLoadingAvailableThemes, isFalse);
    });

    test('importRegistryThemeFile adds theme to registry and selects it', () async {
      final c = ThemeController.instance;
      await c.load();
      final source = File(p.join('test/fixtures/themes', 'querya_custom_dark.json'));

      final result = await c.importRegistryThemeFile(source.path);

      expect(result, isA<ThemeDefinitionImportSuccess>());
      expect(c.selectedThemeId, 'fixture-custom-dark');
      expect(
        c.availableThemes.map((theme) => theme.id),
        contains('fixture-custom-dark'),
      );
      expect(c.activeTheme.colorScheme.primary, parseQueryaThemeColor('#38BDF8'));
    });
  });
}
