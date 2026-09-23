import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_workspace.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  late String dbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    tempDir = await Directory.systemTemp.createTemp('querya_sql_guard_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();

    dbPath = '${tempDir.path}/test.db';
    final db = await databaseFactoryFfi.openDatabase(dbPath);
    await db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);');
    await db.execute("INSERT INTO users VALUES (1, 'Alice');");
    await db.close();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  tearDown(() {
    SqlEditorCommandBridge.instance.unregister(connectionId: 501);
  });

  testWidgets('SQL Execute prompts discard dialog when staging buffer is dirty and preserves buffer on Cancel',
      (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));

    final conn = ConnectionRow(
      id: 501,
      type: 'sqlite',
      name: 'Test SQLite',
      host: dbPath,
      createdAt: '2026-09-24T00:00:00Z',
    );

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox.expand(
          child: SqliteSqlWorkspace(
            connectionRow: conn,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final workspaceState = tester.state(find.byType(SqliteSqlWorkspace));
    final dynamic dynamicState = workspaceState;
    final dynamic activeSession = dynamicState.activeSession;
    expect(activeSession, isNotNull);

    activeSession.controller.text = 'SELECT * FROM users;';
    activeSession.columns = ['id', 'name'];
    activeSession.rows = [['1', 'Alice']];
    final buffer = DataGridStagingBuffer(
      columns: ['id', 'name'],
      rows: [['1', 'Alice']],
    );
    activeSession.stagingBuffer = buffer;

    // Stage an edit in the buffer
    buffer.setCell(0, 1, 'Bob');
    expect(buffer.isDirty, isTrue);

    // 1. Press Execute while buffer is dirty
    final executeBtn = find.widgetWithText(OutlineButton, 'Execute (F5)');
    expect(executeBtn, findsOneWidget);

    // 3. Press Execute again while buffer is dirty
    await tester.tap(executeBtn);
    await tester.pumpAndSettle();

    // Confirmation dialog should be visible
    expect(find.text('Unsaved changes in "Query 1"'), findsOneWidget);
    expect(
      find.text(
        'This table has 1 pending change that have not been saved. Continuing will discard them.',
      ),
      findsOneWidget,
    );

    // 4. Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Dialog closed, buffer is still dirty and NOT disposed
    expect(find.text('Unsaved changes in "Query 1"'), findsNothing);
    expect(buffer.isDirty, isTrue);
    expect(activeSession.stagingBuffer, same(buffer));

    // 5. Press Execute again and choose Discard
    await tester.tap(executeBtn);
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes in "Query 1"'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();

    // Query was allowed to run, previous dirty buffer was discarded
    expect(find.text('Unsaved changes in "Query 1"'), findsNothing);
    final DataGridStagingBuffer? newBuffer =
        activeSession.stagingBuffer as DataGridStagingBuffer?;
    expect(newBuffer == null || !newBuffer.isDirty, isTrue);

    material.FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
