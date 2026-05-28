import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_preset.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
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
}
