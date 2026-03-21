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
void _expectTextCount(String label, int expected) {
  final n = find.text(label).evaluate().length;
  expect(n, expected, reason: 'Text("$label"): expected $expected, found $n');
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
    setUp(() async {
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      await FoldersStorage.instance.reload();
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
      await LocalDb.instance.addFolder('LayoutTestFolder');
      final folderId =
          await LocalDb.instance.getFolderIdByName('LayoutTestFolder');
      expect(folderId, isNotNull);

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
      // ConnectionsPanel loads folders async; do not use pumpAndSettle (chevron animation).
      // Do not wrap the whole pump loop in expectNoLayoutOverflow: transient frames during
      // async load / chevron animation can report overflow-like errors on CI while the
      // settled layout is fine — only assert overflow on the final frame.
      var folderVisible = false;
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('LayoutTestFolder').evaluate().isNotEmpty) {
          folderVisible = true;
          break;
        }
      }
      expect(
        folderVisible,
        isTrue,
        reason:
            'LayoutTestFolder did not appear after async load (FoldersStorage / LocalDb)',
      );

      await expectNoLayoutOverflow(() async {
        await tester.pump();
      });

      _expectTextCount('LayoutTestFolder', 1);
      _expectTextCount('PG local', 1);
      _expectTextCount('Redis local', 1);
      _expectTextCount('Mongo local', 1);
    });
  });
}
