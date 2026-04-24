import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
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
    tempDir = await Directory.systemTemp.createTemp('querya_local_db_secrets_');
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

  group('LocalDb secrets', () {
    test('addConnection leaves password out of SQLite', () async {
      const row = ConnectionRow(
        type: 'redis',
        name: 'R1',
        host: '127.0.0.1',
        port: 6379,
        password: 'redis-secret',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);

      final dbFile = p.join(tempDir.path, 'querya_desktop', 'querya.db');
      await LocalDb.instance.close();
      sqfliteFfiInit();
      final raw = await databaseFactoryFfi.openDatabase(
        dbFile,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final maps = await raw.query('connections', where: 'id = ?', whereArgs: [id]);
        expect(maps.single['password'], isNull);
      } finally {
        await raw.close();
      }

      final list = await LocalDb.instance.getConnections();
      final loaded = list.singleWhere((c) => c.id == id);
      expect(loaded.password, 'redis-secret');
    });

    test('removeConnection deletes secure-store entries', () async {
      const row = ConnectionRow(
        type: 'redis',
        name: 'R2',
        host: '127.0.0.1',
        port: 6379,
        password: 'x',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);
      await LocalDb.instance.removeConnection(id);

      final s = await ConnectionSecretsStore.readForConnection(id);
      expect(s.password, isNull);
      expect(s.connectionString, isNull);
    });
  });
}
