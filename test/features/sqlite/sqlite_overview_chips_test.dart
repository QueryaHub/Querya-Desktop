import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/sqlite/sqlite_overview_tab.dart';
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    tempDir = await Directory.systemTemp.createTemp('querya_overview_chips_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
    dbPath = '${tempDir.path}/chips.db';
    final db = await databaseFactoryFfi.openDatabase(dbPath);
    await db.execute('CREATE TABLE orders (id INTEGER PRIMARY KEY);');
    await db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY);');
    await db.close();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a table chip opens that table (#1816)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final opened = <String>[];
    final conn = ConnectionRow(
      id: 601,
      type: 'sqlite',
      name: 'Chips',
      host: dbPath,
      createdAt: '2026-10-25T00:00:00Z',
    );

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: SqliteOverviewTab(connectionRow: conn, onOpenTable: opened.add),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(find.text('users'), findsOneWidget);
    await tester.tap(find.text('users'));
    await tester.pump();
    expect(opened, ['users']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
