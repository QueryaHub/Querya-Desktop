import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/demo/demo_playground_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_demo_service_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('DemoPlaygroundService resolves path and seeds demo SQLite database', () async {
    final dbPath = await DemoPlaygroundService.resolveDemoDatabasePath();
    expect(dbPath.endsWith('demo_playground.sqlite'), isTrue);

    await DemoPlaygroundService.seedDemoDatabase(dbPath);
    expect(File(dbPath).existsSync(), isTrue);

    final db = await databaseFactoryFfi.openDatabase(dbPath);
    try {
      final users = await db.rawQuery('SELECT * FROM users;');
      expect(users.length, equals(8));

      final products = await db.rawQuery('SELECT * FROM products;');
      expect(products.length, equals(8));

      final orders = await db.rawQuery('SELECT * FROM orders;');
      expect(orders.length, equals(12));
    } finally {
      await db.close();
    }

    // Calling seedDemoDatabase a second time must be idempotent
    await DemoPlaygroundService.seedDemoDatabase(dbPath);
    final db2 = await databaseFactoryFfi.openDatabase(dbPath);
    try {
      final users2 = await db2.rawQuery('SELECT * FROM users;');
      expect(users2.length, equals(8));
    } finally {
      await db2.close();
    }
  });

  test('DemoPlaygroundService getOrCreateDemoConnection creates and reuses connection row', () async {
    final conn1 = await DemoPlaygroundService.getOrCreateDemoConnection();
    expect(conn1.name, equals(DemoPlaygroundService.demoConnectionName));
    expect(conn1.type, equals('sqlite'));
    expect(conn1.id, isNotNull);

    final conn2 = await DemoPlaygroundService.getOrCreateDemoConnection();
    expect(conn2.id, equals(conn1.id));
    expect(conn2.name, equals(conn1.name));
  });

  test('DemoPlaygroundService demoDefaultQuery is non-empty and contains key tables', () {
    const query = DemoPlaygroundService.demoDefaultQuery;
    expect(query.contains('FROM orders'), isTrue);
    expect(query.contains('JOIN users'), isTrue);
    expect(query.contains('JOIN products'), isTrue);
  });
}
