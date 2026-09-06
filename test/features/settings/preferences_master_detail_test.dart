import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/settings/preferences_controls.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
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
    tempDir = await Directory.systemTemp
        .createTemp('querya_preferences_master_detail_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
    await AppSettings.instance.getCheckForUpdatesOnStartup();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildTestApp({
    PreferencesCategory? initialCategory,
  }) {
    return ShadcnApp(
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: material.Scaffold(
        body: material.Builder(
          builder: (context) {
            return material.ElevatedButton(
              onPressed: () => showPreferencesDialog(
                context,
                initialCategory: initialCategory,
              ),
              child: const material.Text('Open Preferences'),
            );
          },
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Open Preferences'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Preferences Master-Detail Dialog', () {
    testWidgets('renders categories in master rail and defaults to General',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await openDialog(tester);

      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('General'), findsAtLeastNWidgets(1));
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('SQL & Editor'), findsOneWidget);
      expect(find.text('Data Grid'), findsOneWidget);
      expect(find.text('Extensions'), findsOneWidget);
      expect(find.text('Shortcuts'), findsOneWidget);
      expect(find.text('About & Storage'), findsOneWidget);

      // Default category is General
      expect(find.text('General Settings'), findsOneWidget);
    });

    testWidgets('switching category switches active pane', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await openDialog(tester);

      // Tap on Shortcuts category in the rail
      await tester.tap(find.text('Shortcuts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Execute query / selection'), findsOneWidget);
      expect(find.text('Auto-fit column width'), findsOneWidget);

      // Tap on About category
      await tester.tap(find.text('About & Storage'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Querya Desktop'), findsOneWidget);
      expect(find.text('Fast, native multi-database management studio.'),
          findsOneWidget);
    });

    testWidgets('deep links directly to specified initialCategory',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(initialCategory: PreferencesCategory.sql),
      );
      await openDialog(tester);

      // Should be directly in SQL Editor pane
      expect(find.text('SQL & Query Execution'), findsOneWidget);
      expect(find.text('PostgreSQL timeout'), findsOneWidget);
    });

    testWidgets('search bar filters preferences and updates matches',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await openDialog(tester);

      final searchInput = find.byType(material.TextField);
      expect(searchInput, findsOneWidget);

      await tester.enterText(searchInput, 'timeout');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Match badge should appear on SQL Editor and pane is active
      expect(find.text('SQL & Query Execution'), findsOneWidget);
      expect(find.text('PostgreSQL timeout'), findsOneWidget);
    });

    testWidgets('PreferencesSwitchRow toggles on tap and exposes state',
        (tester) async {
      var currentValue = false;

      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          home: material.Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return PreferencesSwitchRow(
                  title: const material.Text('Auto Commit'),
                  subtitle:
                      const material.Text('Automatically commit transactions'),
                  value: currentValue,
                  onChanged: (val) {
                    setState(() {
                      currentValue = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Auto Commit'), findsOneWidget);
      expect(find.text('Automatically commit transactions'), findsOneWidget);
      expect(find.byType(material.Switch), findsOneWidget);

      await tester.tap(find.text('Auto Commit'));
      await tester.pump();

      expect(currentValue, isTrue);
    });
  });
}
