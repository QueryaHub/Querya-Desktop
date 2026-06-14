import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/theme/theme_paths.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_theme_paths_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ThemePaths', () {
    test('userThemesDirectory resolves under app support', () async {
      final dir = await ThemePaths.userThemesDirectory();

      expect(dir.path, p.join(tempDir.path, 'themes'));
    });

    test('importedThemesDirectory resolves under user themes', () async {
      final dir = await ThemePaths.importedThemesDirectory();

      expect(dir.path, p.join(tempDir.path, 'themes', 'imported'));
    });

    test('path getters do not create directories', () async {
      await ThemePaths.userThemesDirectory();
      await ThemePaths.importedThemesDirectory();

      expect(await Directory(p.join(tempDir.path, 'themes')).exists(), isFalse);
      expect(
        await Directory(p.join(tempDir.path, 'themes', 'imported')).exists(),
        isFalse,
      );
    });

    test('ensureUserThemesDirectory creates themes folder', () async {
      final dir = await ThemePaths.ensureUserThemesDirectory();

      expect(dir.path, p.join(tempDir.path, 'themes'));
      expect(await dir.exists(), isTrue);
    });

    test('ensureImportedThemesDirectory creates imported folder', () async {
      final dir = await ThemePaths.ensureImportedThemesDirectory();

      expect(dir.path, p.join(tempDir.path, 'themes', 'imported'));
      expect(await dir.exists(), isTrue);
    });

    test('legacyDotQueryaThemesDirectory resolves ~/.querya/themes', () async {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) {
        expect(await ThemePaths.legacyDotQueryaThemesDirectory(), isNull);
        return;
      }

      final dir = await ThemePaths.legacyDotQueryaThemesDirectory();

      expect(dir, isNotNull);
      expect(dir!.path, p.join(home, '.querya', 'themes'));
      expect(await dir.exists(), isFalse);
    });
  });
}
