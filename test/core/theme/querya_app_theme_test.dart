import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:flutter/material.dart' as material;

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
    tempDir = await Directory.systemTemp.createTemp('querya_app_theme_test_');
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
  });

  test('ThemeController material themes differ for light vs dark background',
      () async {
    final controller = ThemeController.instance;
    await controller.load();

    expect(
      controller.darkMaterialTheme.colorScheme.surface,
      QueryaTheme.darkDefault.colors.popover,
    );
    expect(
      controller.lightMaterialTheme.colorScheme.surface,
      QueryaTheme.lightDefault.colors.popover,
    );
    expect(
      controller.darkMaterialTheme.colorScheme.surface,
      isNot(controller.lightMaterialTheme.colorScheme.surface),
    );
  });

  test('setThemeMode switches activeTheme and material surface', () async {
    final controller = ThemeController.instance;
    await controller.load();

    expect(
      controller.activeTheme.colors.background,
      QueryaTheme.darkDefault.colors.background,
    );

    await controller.setThemeMode(material.ThemeMode.light);

    expect(
      controller.activeTheme.colors.background,
      QueryaTheme.lightDefault.colors.background,
    );
    expect(
      controller.darkMaterialTheme.colorScheme.surface,
      isNot(controller.lightMaterialTheme.colorScheme.surface),
    );
  });
}
