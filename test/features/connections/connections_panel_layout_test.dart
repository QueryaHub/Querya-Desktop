import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/layout_overflow.dart';

String _isoNow() => DateTime.now().toUtc().toIso8601String();

/// Avoid [findsOneWidget] here: it polls until a long timeout and can hang the suite.
/// Match [material.Text] explicitly (same as folder / connection rows in [ConnectionsPanel]).
void _expectMaterialTextCount(String label, int expected) {
  final n = find.widgetWithText(material.Text, label).evaluate().length;
  expect(
    n,
    expected,
    reason: 'material.Text("$label"): expected $expected, found $n',
  );
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

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_conn_panel_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
    // LocalDb is a singleton: if it was already opened in this isolate (e.g. another
    // test file ran first), the DB path would be wrong. Force reopen with fake path.
    await LocalDb.instance.close();
    // Pre-load FoldersStorage so _migrateFromLegacyIfNeeded() (which uses
    // dart:io File.exists()) runs here in real async — it would hang inside
    // testWidgets' FakeAsync zone.
    await FoldersStorage.instance.reload();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ConnectionsPanel layout', () {
    final sizes = <String, material.Size>{
      'narrow_tall': const material.Size(320, 720),
      'very_narrow': const material.Size(280, 560),
      'medium': const material.Size(900, 640),
    };

    for (final entry in sizes.entries) {
      testWidgets('no layout overflow at ${entry.key} ${entry.value}',
          (tester) async {
        await expectNoLayoutOverflow(() async {
          await pumpWidgetWithSurfaceSize(
            tester,
            entry.value,
            ShadcnApp(
              theme: AppTheme.dark,
              darkTheme: AppTheme.dark,
              themeMode: ThemeMode.dark,
              home: material.SizedBox.expand(
                child: ConnectionsPanel(
                  onPostgresOpenSqlWorkspace: (_) {},
                ),
              ),
            ),
          );
        });
      });
    }
  });

  group('ConnectionsPanel expanded folder (tree)', () {
    // ALL data seeding happens in setUp which runs in REAL async (outside
    // FakeAsync). This is critical: FoldersStorage.reload() internally calls
    // File.exists() (dart:io) which never completes in FakeAsync, and sqflite
    // FFI query Futures also need real-zone microtask processing.
    setUp(() async {
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      await LocalDb.instance.close();

      await LocalDb.instance.addFolder('LayoutTestFolder');
      final folderId =
          await LocalDb.instance.getFolderIdByName('LayoutTestFolder');

      await LocalDb.instance.addConnection(
        ConnectionRow(
          type: 'postgresql',
          name: 'PG local',
          host: '127.0.0.1',
          port: 5432,
          createdAt: _isoNow(),
          folderId: folderId,
        ),
      );
      await LocalDb.instance.addConnection(
        ConnectionRow(
          type: 'redis',
          name: 'Redis local',
          host: '127.0.0.1',
          port: 6379,
          createdAt: _isoNow(),
          folderId: folderId,
        ),
      );
      await LocalDb.instance.addConnection(
        ConnectionRow(
          type: 'mongodb',
          name: 'Mongo local',
          host: '127.0.0.1',
          port: 27017,
          createdAt: _isoNow(),
          folderId: folderId,
        ),
      );
      await FoldersStorage.instance.reload();

      // Close the DB so _open() creates a FRESH Database object inside
      // FakeAsync zone (testWidgets). sqflite's internal Lock retains the zone
      // where the Database was created; if it stays in the real-async zone,
      // Lock._last Future continuations go to the wrong microtask queue and
      // _loadData() never completes.
      await LocalDb.instance.close();
    });

    tearDown(() async {
      final conns = await LocalDb.instance.getConnections();
      for (final c in conns) {
        if (c.id != null) await LocalDb.instance.removeConnection(c.id!);
      }
      for (final name in await LocalDb.instance.getFolders()) {
        await LocalDb.instance.removeFolder(name);
      }
      await FoldersStorage.instance.reload();
    });

    testWidgets(
        'narrow panel: expanded folder lists pg / redis / mongo rows without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const material.Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: material.SizedBox.expand(
            child: ConnectionsPanel(
              onPostgresOpenSqlWorkspace: (_) {},
            ),
          ),
        ),
      );

      // _loadData() fires from initState and calls sqflite queries. sqflite
      // internally uses Lock whose _last Future lives in the real-async zone
      // (because the DB was first opened in setUp). Each cross-zone Future hop
      // needs one runAsync (to process the real-zone microtask) + pump (to
      // process the resulting FakeAsync microtask and frame).
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump(const Duration(milliseconds: 50));
      }

      _expectMaterialTextCount('LayoutTestFolder', 1);
      _expectMaterialTextCount('PG local', 1);
      _expectMaterialTextCount('Redis local', 1);
      _expectMaterialTextCount('Mongo local', 1);
    });
  });
}
