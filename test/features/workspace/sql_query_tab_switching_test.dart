import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_workspace.dart';
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

  setUpAll(() async {
    sqfliteFfiInit();
    tempDir = await Directory.systemTemp.createTemp('querya_tab_switch_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
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
    SqlEditorCommandBridge.instance.unregister(connectionId: 777);
  });

  testWidgets(
      'switching SQL tabs reuses cached panes instead of rebuilding every tab',
      (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));

    final conn = ConnectionRow(
      id: 777,
      type: 'sqlite',
      name: 'Test SQLite',
      host: '${tempDir.path}/tab_switch.db',
      createdAt: '2026-09-27T00:00:00Z',
    );

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox.expand(
          child: SqliteSqlWorkspace(connectionRow: conn),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(SqliteSqlWorkspace));
    final addTabButton =
        find.byKey(const material.ValueKey('querya_tab_add_button'));

    // Add two more tabs (three total), each pane is built exactly once.
    await tester.tap(addTabButton);
    await tester.pumpAndSettle();
    await tester.tap(addTabButton);
    await tester.pumpAndSettle();

    expect(state.paneBuildCount, 3);

    // Mutate the (currently active, third) tab's own state, which is allowed
    // to rebuild its own pane, then settle.
    final dynamic activeSession = state.activeSession;
    activeSession.controller.text = 'SELECT 1;';
    await tester.pump();

    final buildCountBeforeSwitching = state.paneBuildCount as int;

    // Switching tabs back and forth must not rebuild any pane: only the tab
    // strip and the swapped IndexedStack index should change.
    await tester.tap(find.byKey(const material.ValueKey('querya_tab_Query 1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const material.ValueKey('querya_tab_Query 2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const material.ValueKey('querya_tab_Query 3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const material.ValueKey('querya_tab_Query 1')));
    await tester.pumpAndSettle();

    expect(state.paneBuildCount, buildCountBeforeSwitching);

    material.FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const material.SizedBox());
    await tester.pumpAndSettle();
  });
}
