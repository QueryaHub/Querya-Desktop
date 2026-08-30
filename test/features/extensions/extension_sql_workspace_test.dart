import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/extensions/extension_sql_workspace.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

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
    tempDir = await Directory.systemTemp.createTemp('querya_ext_sql_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
  });

  const testConn = ConnectionRow(
    id: 99,
    type: 'clickhouse-ext',
    name: 'ClickHouse Analytics',
    host: 'localhost',
    port: 8123,
    extensionId: 'querya.clickhouse',
    createdAt: '2026-08-29T10:00:00Z',
  );

  group('ExtensionSqlWorkspace destructive SQL confirmation', () {
    setUp(() async {
      await AppSettings.instance.setConfirmDestructiveOperations(true);
    });

    tearDown(() async {
      SqlEditorCommandBridge.instance.unregister(connectionId: 99);
      await ExtensionDriverSession.instance.disconnectAll();
    });

    test('DestructiveSqlDetector detects destructive statements in ClickHouse / extension SQL', () {
      final dropTable = DestructiveSqlDetector.inspect('DROP TABLE analytics.events;');
      expect(dropTable.isDestructive, isTrue);
      expect(dropTable.operations.any((o) => o.type == DestructiveSqlType.dropTable), isTrue);

      final truncateTable = DestructiveSqlDetector.inspect('TRUNCATE TABLE metrics;');
      expect(truncateTable.isDestructive, isTrue);
      expect(truncateTable.operations.any((o) => o.type == DestructiveSqlType.truncateTable), isTrue);

      final selectQuery = DestructiveSqlDetector.inspect('SELECT * FROM analytics.events LIMIT 10;');
      expect(selectQuery.isDestructive, isFalse);
    });

    testWidgets('shows Destructive Operation Detected dialog when running DROP TABLE and dismisses on Cancel', (tester) async {
      await tester.binding.setSurfaceSize(const material.Size(1024, 768));

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.SizedBox.expand(
            child: ExtensionSqlWorkspace(
              connectionRow: testConn,
              initialSql: 'DROP TABLE analytics.raw_hits;',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find Execute button in SQL editor chrome
      final executeBtn = find.widgetWithText(OutlineButton, 'Execute (F5)');
      expect(executeBtn, findsOneWidget);

      await tester.tap(executeBtn);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // Confirmation dialog must appear
      expect(find.text('Destructive Operation Detected'), findsOneWidget);
      expect(find.text('Target connection: ClickHouse Analytics'), findsOneWidget);
      expect(find.text('DROP TABLE'), findsOneWidget);
      expect(find.text('DROP TABLE analytics.raw_hits;'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);

      // Dismiss by clicking Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Destructive Operation Detected'), findsNothing);
      material.FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
