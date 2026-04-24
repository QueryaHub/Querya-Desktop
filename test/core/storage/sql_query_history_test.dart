import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../memory_secrets_backend.dart';

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
    tempDir = await Directory.systemTemp.createTemp('querya_sql_history_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    testMemorySecrets.clear();
    for (final c in await LocalDb.instance.getConnections()) {
      if (c.id != null) await LocalDb.instance.removeConnection(c.id!);
    }
  });

  group('Sql query history', () {
    test('records and lists newest first', () async {
      const row = ConnectionRow(
        type: 'postgres',
        name: 'P1',
        host: '127.0.0.1',
        port: 5432,
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);

      await LocalDb.instance.recordSqlQueryHistory(
        connectionId: id,
        databaseName: null,
        sqlText: 'select 1',
      );
      await LocalDb.instance.recordSqlQueryHistory(
        connectionId: id,
        databaseName: null,
        sqlText: 'select 2',
      );

      final list = await LocalDb.instance.listSqlQueryHistory(
        connectionId: id,
        databaseName: null,
        limit: 10,
      );
      expect(list.map((e) => e.sqlText), ['select 2', 'select 1']);
    });

    test('trims to maxEntries per connection and database bucket', () async {
      const row = ConnectionRow(
        type: 'mysql',
        name: 'M1',
        host: '127.0.0.1',
        port: 3306,
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);

      for (var i = 0; i < 5; i++) {
        await LocalDb.instance.recordSqlQueryHistory(
          connectionId: id,
          databaseName: 'db1',
          sqlText: 'q$i',
          maxEntries: 3,
        );
      }

      final list = await LocalDb.instance.listSqlQueryHistory(
        connectionId: id,
        databaseName: 'db1',
        limit: 10,
      );
      expect(list.map((e) => e.sqlText), ['q4', 'q3', 'q2']);
    });

    test('separate buckets for different database_name', () async {
      const row = ConnectionRow(
        type: 'postgres',
        name: 'P2',
        host: '127.0.0.1',
        port: 5432,
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);

      await LocalDb.instance.recordSqlQueryHistory(
        connectionId: id,
        databaseName: null,
        sqlText: 'on default',
      );
      await LocalDb.instance.recordSqlQueryHistory(
        connectionId: id,
        databaseName: 'other',
        sqlText: 'on other',
      );

      final a = await LocalDb.instance.listSqlQueryHistory(
        connectionId: id,
        databaseName: null,
      );
      final b = await LocalDb.instance.listSqlQueryHistory(
        connectionId: id,
        databaseName: 'other',
      );
      expect(a.single.sqlText, 'on default');
      expect(b.single.sqlText, 'on other');
    });

    test('clearSqlQueryHistoryBucket removes only matching database', () async {
      const row = ConnectionRow(
        type: 'postgres',
        name: 'P3',
        host: '127.0.0.1',
        port: 5432,
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);
      await LocalDb.instance.recordSqlQueryHistory(
        connectionId: id,
        databaseName: null,
        sqlText: 'a',
      );
      await LocalDb.instance.recordSqlQueryHistory(
        connectionId: id,
        databaseName: 'x',
        sqlText: 'b',
      );
      await LocalDb.instance.clearSqlQueryHistoryBucket(
        connectionId: id,
        databaseName: 'x',
      );
      final def = await LocalDb.instance.listSqlQueryHistory(
        connectionId: id,
        databaseName: null,
      );
      final x = await LocalDb.instance.listSqlQueryHistory(
        connectionId: id,
        databaseName: 'x',
      );
      expect(def.single.sqlText, 'a');
      expect(x, isEmpty);
    });

    test('clearSqlQueryHistoryForConnection removes all rows', () async {
      const row = ConnectionRow(
        type: 'redis',
        name: 'R9',
        host: '127.0.0.1',
        port: 6379,
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);
      await LocalDb.instance.recordSqlQueryHistory(
        connectionId: id,
        sqlText: 'x',
      );
      await LocalDb.instance.clearSqlQueryHistoryForConnection(id);
      final list = await LocalDb.instance.listSqlQueryHistory(
        connectionId: id,
        limit: 5,
      );
      expect(list, isEmpty);
    });

    test('removeConnection drops history via FK', () async {
      const row = ConnectionRow(
        type: 'redis',
        name: 'R8',
        host: '127.0.0.1',
        port: 6379,
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);
      await LocalDb.instance.recordSqlQueryHistory(
        connectionId: id,
        sqlText: 'x',
      );
      await LocalDb.instance.removeConnection(id);
      await LocalDb.instance.close();
      sqfliteFfiInit();
      final dbFile = p.join(tempDir.path, 'querya_desktop', 'querya.db');
      final raw = await databaseFactoryFfi.openDatabase(
        dbFile,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final rows =
            await raw.rawQuery('SELECT COUNT(*) AS c FROM sql_query_history');
        expect(rows.first['c'], 0);
      } finally {
        await raw.close();
      }
    });
  });
}
