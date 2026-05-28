import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';

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
        await Directory.systemTemp.createTemp('querya_theme_import_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await ThemeImportService.deletePersistedImport();
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('importFromPath parses fixture and persists copy', () async {
    final fixture = File('test/fixtures/themes/dark_subset.json');
    final result = await ThemeImportService.importFromPath(fixture.path);
    expect(result, isA<ThemeImportSuccess>());
    final success = result as ThemeImportSuccess;
    expect(success.name, 'Fixture Dark Subset');
    expect(success.isDark, isTrue);
    expect(success.colors['editor.background'], '#1e1e1e');

    final reloaded = await ThemeImportService.loadPersistedColors();
    expect(reloaded?['editor.background'], '#1e1e1e');
  });

  test('importFromPath persists tokenColors from dracula fixture', () async {
    final fixture = File('test/fixtures/themes/dracula_tokens.json');
    final result = await ThemeImportService.importFromPath(fixture.path);
    expect(result, isA<ThemeImportSuccess>());
    final success = result as ThemeImportSuccess;
    expect(success.tokenColors, isNotEmpty);

    final tokens = await ThemeImportService.loadPersistedTokenColors();
    expect(tokens.length, success.tokenColors.length);
    expect(tokens.first.scopes, contains('comment'));
  });

  test('importFromPath returns failure for missing file', () async {
    final result =
        await ThemeImportService.importFromPath('/no/such/theme.json');
    expect(result, isA<ThemeImportFailure>());
  });
}
