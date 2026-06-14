import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
import 'package:querya_desktop/core/theme/theme_registry_service.dart';
import 'package:querya_desktop/features/settings/preferences_appearance_section.dart';
import 'package:querya_desktop/features/settings/theme_picker_button.dart';

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
  late ThemeRegistryService registry;

  setUpAll(() async {
    tempDir = await Directory.systemTemp
        .createTemp('querya_preferences_appearance_test_');
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
    ThemeController.instance.setRegistryServiceForTest(
      ThemeRegistryService(
        userThemesDirectory: () async => themesDir,
        importedThemesDirectory: () async => importedDir,
        assetLoader: _fixtureAssetLoader,
      ),
    );
    await AppSettings.instance.clearThemeSettings();
    await ThemeImportService.deletePersistedImport();
    if (await themesDir.exists()) {
      await themesDir.delete(recursive: true);
    }
    await ThemeController.instance.load();
  });

  group('PreferencesAppearanceSection', () {
    Future<void> pumpSection(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const material.Size(1280, 900));
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: material.SizedBox(
              width: 640,
              child: PreferencesAppearanceSection(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows built-in themes in ThemePickerButton', (tester) async {
      await pumpSection(tester);

      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Color preset'), findsNothing);
      expect(find.text('Querya Dark'), findsOneWidget);
      expect(find.byType(ThemePickerButton), findsOneWidget);

      await tester.tap(find.text('Querya Dark'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Querya Light'), findsOneWidget);
    });

    testWidgets('import and reset buttons remain visible', (tester) async {
      await pumpSection(tester);

      expect(find.text('Import theme…'), findsOneWidget);
      expect(find.text('Refresh themes'), findsOneWidget);
      expect(find.text('Open themes folder'), findsOneWidget);
      expect(find.text('Reset appearance'), findsOneWidget);
    });

    testWidgets('shows themes folder hint without live reload promise',
        (tester) async {
      await pumpSection(tester);

      expect(
        find.textContaining('Themes are loaded from the app support themes folder'),
        findsOneWidget,
      );
      expect(find.textContaining('not watched automatically'), findsOneWidget);
      expect(find.textContaining('live reload'), findsNothing);
    });
  });
}
