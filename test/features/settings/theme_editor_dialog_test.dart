import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_editor_draft.dart';
import 'package:querya_desktop/core/theme/theme_registry_service.dart';
import 'package:querya_desktop/features/settings/theme_editor_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

Future<String> _fixtureAssetLoader(String assetPath) async {
  final fileName = p.basename(assetPath);
  return File(p.join('test/fixtures/themes', fileName)).readAsString();
}

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
  late Directory themesDir;
  late Directory importedDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_theme_editor_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  setUp(() async {
    themesDir = Directory(p.join(tempDir.path, 'themes'));
    importedDir = Directory(p.join(themesDir.path, 'imported'));
    await importedDir.create(recursive: true);

    final registry = ThemeRegistryService(
      userThemesDirectory: () async => themesDir,
      importedThemesDirectory: () async => importedDir,
      assetLoader: _fixtureAssetLoader,
    );
    ThemeController.instance.setRegistryServiceForTest(registry);
    await ThemeController.instance.load();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    await AppSettings.instance.clearThemeSettings();
    if (await themesDir.exists()) {
      await themesDir.delete(recursive: true);
    }
  });

  group('ThemeEditorDialog', () {
    testWidgets('renders dialog header, fields, and action buttons', (tester) async {
      await tester.binding.setSurfaceSize(const material.Size(1280, 900));
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.Builder(
              builder: (context) => material.ElevatedButton(
                onPressed: () => showThemeEditorDialog(context),
                child: const material.Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open modal dialog
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify header and elements
      expect(find.text('Theme Studio'), findsOneWidget);
      expect(find.text('Reset from current'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // Verify token color field labels
      for (final field in themeEditorMvpColorFields) {
        expect(find.text(field.label), findsWidgets);
      }

      // Close modal
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Theme Studio'), findsNothing);
    });
  });
}
