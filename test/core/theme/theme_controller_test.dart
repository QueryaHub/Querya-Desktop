import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_preset.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('querya_theme_controller_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    await AppSettings.instance.clearThemeSettings();
    await ThemeController.instance.load();
  });

  test('load defaults to dark preset', () async {
    final c = ThemeController.instance;
    await c.load();
    expect(c.themeMode, ThemeMode.dark);
    expect(c.preset, QueryaThemePreset.queryaDark);
    expect(c.activeTheme, QueryaTheme.darkDefault);
    expect(c.isLoaded, isTrue);
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
}
