import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/connections/driver_manager_dialog.dart';
import 'package:querya_desktop/features/mysql/mysql_workspace_home.dart';
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

  @override
  Future<String?> getApplicationCachePath() async => _root;

  @override
  Future<String?> getLibraryPath() async => _root;

  @override
  Future<String?> getExternalStoragePath() async => _root;

  @override
  Future<List<String>?> getExternalCachePaths() async => [_root];

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async =>
      [_root];

  @override
  Future<String?> getDownloadsPath() async => _root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final myConn = ConnectionRow(
    id: 2,
    type: 'mysql',
    name: 'Test MySQL',
    host: '127.0.0.1',
    port: 3306,
    createdAt: '2026-01-01T00:00:00.000Z',
  );

  group('MysqlWorkspaceHome', () {
    testWidgets('shows tabs and SQL tab exposes Execute control', (tester) async {
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: material.Scaffold(
            body: material.SizedBox(
              width: 700,
              height: 500,
              child: MysqlWorkspaceHome(connectionRow: myConn),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('MySQL'), findsOneWidget);
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('SQL'), findsOneWidget);

      await tester.tap(find.text('SQL'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Execute'), findsWidgets);
    });
  });

  group('Driver Manager dialog', () {
    testWidgets('showDriverManagerDialog shows built-in drivers copy', (tester) async {
      await tester.binding.setSurfaceSize(const material.Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late material.BuildContext ctx;
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: material.Builder(
            builder: (c) {
              ctx = c;
              return material.TextButton(
                onPressed: () => showDriverManagerDialog(ctx),
                child: const material.Text('open-drivers'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open-drivers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Driver Manager'), findsOneWidget);
      expect(find.textContaining('built-in Dart'), findsWidgets);
    });
  });

  group('Preferences dialog', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp
          .createTemp('querya_prefs_dialog_test_');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      await LocalDb.initFfi();
      await LocalDb.instance.close();
    });

    tearDownAll(() async {
      await LocalDb.instance.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('showPreferencesDialog shows preferences title', (tester) async {
      late material.BuildContext ctx;
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: material.Builder(
            builder: (c) {
              ctx = c;
              return material.TextButton(
                onPressed: () => showPreferencesDialog(ctx),
                child: const material.Text('open-prefs'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open-prefs'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Preferences'), findsOneWidget);
    });
  });
}
