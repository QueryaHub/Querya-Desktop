import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

String _isoNow() => DateTime.now().toUtc().toIso8601String();

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

  group('TreeObjectFilterBar', () {
    testWidgets('renders input, badges, and triggers callbacks', (tester) async {
      final controller = material.TextEditingController();
      addTearDown(controller.dispose);
      String lastChanged = '';
      bool cleared = false;

      Widget buildWidget({required int filtered, required int total}) {
        return ShadcnApp(
          theme: AppTheme.dark,
          home: material.Scaffold(
            body: material.SizedBox(
              width: 300,
              child: TreeObjectFilterBar(
                controller: controller,
                hintText: 'Filter tables...',
                onChanged: (val) => lastChanged = val,
                onClear: () => cleared = true,
                filteredCount: filtered,
                totalCount: total,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildWidget(filtered: 10, total: 10));
      expect(find.byType(material.TextField), findsOneWidget);
      expect(find.text('Filter tables...'), findsOneWidget);
      // When controller text is empty, count badge is hidden
      expect(find.text('10/10'), findsNothing);

      // Enter text
      await tester.enterText(find.byType(material.TextField), 'users');
      await tester.pump();
      expect(lastChanged, 'users');

      // Rebuild with filtered count
      await tester.pumpWidget(buildWidget(filtered: 2, total: 10));
      expect(find.text('2/10'), findsOneWidget);
      expect(find.byIcon(material.Icons.close_rounded), findsOneWidget);

      // Tap clear
      await tester.tap(find.byIcon(material.Icons.close_rounded));
      expect(cleared, isTrue);
    });
  });

  group('ConnectionsPanel global search and tree filtering', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('querya_quick_search_test_');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      await LocalDb.initFfi();
      await LocalDb.instance.close();
      await FoldersStorage.instance.reload();
    });

    tearDownAll(() async {
      await LocalDb.instance.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    setUp(() async {
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      await LocalDb.instance.close();

      await LocalDb.instance.addFolder('Production');
      final folderId = await LocalDb.instance.getFolderIdByName('Production');

      await LocalDb.instance.addConnection(
        ConnectionRow(
          type: 'postgresql',
          name: 'Prod Postgres',
          host: 'pg.prod.internal',
          port: 5432,
          databaseName: 'ecommerce',
          createdAt: _isoNow(),
          folderId: folderId,
        ),
      );
      await LocalDb.instance.addConnection(
        ConnectionRow(
          type: 'mysql',
          name: 'Prod MySQL',
          host: 'mysql.prod.internal',
          port: 3306,
          databaseName: 'billing',
          createdAt: _isoNow(),
          folderId: folderId,
        ),
      );
      await LocalDb.instance.addConnection(
        ConnectionRow(
          type: 'sqlite',
          name: 'Local Analytics',
          databaseName: '/tmp/analytics.db',
          createdAt: _isoNow(),
        ),
      );
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

    testWidgets('global search filters connections and auto-expands folder', (tester) async {
      final panelKey = GlobalKey<ConnectionsPanelState>();

      await tester.binding.setSurfaceSize(const material.Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          home: material.SizedBox(
            width: 400,
            height: 700,
            child: ConnectionsPanel(
              key: panelKey,
              skipInitialDbLoadForTest: true,
            ),
          ),
        ),
      );

      final state = panelKey.currentState!;
      await tester.runAsync(() async {
        await state.reloadConnectionsFromDb();
      });
      await tester.pump();

      // Initial state: all connections present
      expect(find.text('SERVERS'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // 3 total connections
      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Local Analytics'), findsOneWidget);

      // Filter by 'analytics'
      state.setSearchQueryForTest('analytics');
      await tester.pump();

      expect(find.text('Local Analytics'), findsOneWidget);
      expect(find.text('Prod Postgres'), findsNothing);
      expect(find.text('Prod MySQL'), findsNothing);
      expect(find.text('1/3'), findsOneWidget);

      // Filter by 'postgres' (inside 'Production' folder)
      state.setSearchQueryForTest('postgres');
      await tester.pump();

      expect(find.text('Prod Postgres'), findsOneWidget);
      expect(find.text('Prod MySQL'), findsNothing);
      expect(find.text('Local Analytics'), findsNothing);
      expect(find.text('1/3'), findsOneWidget);

      // Filter with no match
      state.setSearchQueryForTest('nonexistent_server');
      await tester.pump();

      expect(find.text('No connections match "nonexistent_server"'), findsOneWidget);
      expect(find.text('0/3'), findsOneWidget);

      // Reset search
      state.setSearchQueryForTest('');
      await tester.pump();

      expect(find.text('Local Analytics'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // Filter by database name
      state.setSearchQueryForTest('ecommerce');
      await tester.pump();
      expect(find.text('Prod Postgres'), findsOneWidget);
      expect(find.text('Local Analytics'), findsNothing);

      // Filter by host
      state.setSearchQueryForTest('mysql.prod.internal');
      await tester.pump();
      expect(find.text('Prod MySQL'), findsOneWidget);
      expect(find.text('Prod Postgres'), findsNothing);
    });

    test('pinned items sorting partitions pinned objects to top', () {
      final items = ['users', 'orders', 'products', 'accounts', 'order_items'];
      final pinned = {'products', 'order_items'};

      final sorted = [
        ...items.where((it) => pinned.contains(it)),
        ...items.where((it) => !pinned.contains(it)),
      ];

      expect(sorted, ['products', 'order_items', 'users', 'orders', 'accounts']);

      // Case-insensitive filtering on items
      const query = 'ord';
      final matching = items.where((it) => it.toLowerCase().contains(query)).toList();
      final sortedMatching = [
        ...matching.where((it) => pinned.contains(it)),
        ...matching.where((it) => !pinned.contains(it)),
      ];

      expect(sortedMatching, ['order_items', 'orders']);
    });
  });
}
