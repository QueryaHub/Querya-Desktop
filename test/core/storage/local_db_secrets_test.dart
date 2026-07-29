import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
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
  Future<List<String>?> getExternalStoragePaths(
          {StorageDirectory? type}) async =>
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
        final maps =
            await raw.query('connections', where: 'id = ?', whereArgs: [id]);
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

    test(
        'updateConnection atomically updates SQLite row and secure-store secrets',
        () async {
      const initialRow = ConnectionRow(
        type: 'postgres',
        name: 'PG_Init',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'old-secret-password',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(initialRow);

      final updatedRow = ConnectionRow(
        id: id,
        type: 'postgres',
        name: 'PG_Updated',
        host: 'db.example.com',
        port: 5433,
        username: 'root',
        password: 'new-secret-password',
        connectionString:
            'postgres://root:new-secret-password@db.example.com:5433/mydb',
        createdAt: '2026-01-01T00:00:00Z',
      );
      await LocalDb.instance.updateConnection(updatedRow);

      final list = await LocalDb.instance.getConnections();
      final loaded = list.singleWhere((c) => c.id == id);
      expect(loaded.name, 'PG_Updated');
      expect(loaded.host, 'db.example.com');
      expect(loaded.port, 5433);
      expect(loaded.username, 'root');
      expect(loaded.password, 'new-secret-password');
      expect(loaded.connectionString,
          'postgres://root:new-secret-password@db.example.com:5433/mydb');

      final secrets = await ConnectionSecretsStore.readForConnection(id);
      expect(secrets.password, 'new-secret-password');
      expect(secrets.connectionString,
          'postgres://root:new-secret-password@db.example.com:5433/mydb');
    });

    test(
        'removeConnection still deletes SQLite row when secure-store delete fails',
        () async {
      const row = ConnectionRow(
        type: 'redis',
        name: 'R3',
        host: '127.0.0.1',
        port: 6379,
        password: 'x',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);
      testMemorySecrets.failNextDelete = StateError('libsecret unavailable');

      await LocalDb.instance.removeConnection(id);

      final list = await LocalDb.instance.getConnections();
      expect(list.where((c) => c.id == id), isEmpty);
    });

    test('addConnection rolls back SQLite row when secure-store write fails',
        () async {
      testMemorySecrets.failNextWrite = StateError('keychain write failed');
      const row = ConnectionRow(
        type: 'redis',
        name: 'R4',
        host: '127.0.0.1',
        port: 6379,
        password: 'secret',
        createdAt: '2026-01-01T00:00:00Z',
      );

      await expectLater(
        LocalDb.instance.addConnection(row),
        throwsA(isA<StateError>()),
      );

      final list = await LocalDb.instance.getConnections();
      expect(list.where((c) => c.name == 'R4'), isEmpty);
    });

    test(
        'updateConnection rolls back SQLite and secrets when secure-store write fails',
        () async {
      const initialRow = ConnectionRow(
        type: 'postgres',
        name: 'PG_Before',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'old-password',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(initialRow);

      testMemorySecrets.failNextWrite = StateError('keychain write failed');
      final updatedRow = ConnectionRow(
        id: id,
        type: 'postgres',
        name: 'PG_After',
        host: 'db.example.com',
        port: 5433,
        username: 'root',
        password: 'new-password',
        createdAt: '2026-01-01T00:00:00Z',
      );

      await expectLater(
        LocalDb.instance.updateConnection(updatedRow),
        throwsA(isA<StateError>()),
      );

      final list = await LocalDb.instance.getConnections();
      final loaded = list.singleWhere((c) => c.id == id);
      expect(loaded.name, 'PG_Before');
      expect(loaded.host, 'localhost');
      expect(loaded.port, 5432);
      expect(loaded.username, 'admin');
      expect(loaded.password, 'old-password');
    });

    test(
        'mergeSecretsForConnectionUpdate keeps password when form leaves it blank',
        () async {
      const initialRow = ConnectionRow(
        type: 'postgresql',
        name: 'PG',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'keep-me',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(initialRow);

      final edited = ConnectionRow(
        id: id,
        type: 'postgresql',
        name: 'PG Renamed',
        host: 'db.example.com',
        port: 5432,
        username: 'admin',
        password: null,
        createdAt: '2026-01-01T00:00:00Z',
      );
      final merged = await mergeSecretsForConnectionUpdate(edited);
      expect(merged.password, 'keep-me');
      expect(merged.name, 'PG Renamed');
      expect(merged.host, 'db.example.com');

      await LocalDb.instance.updateConnection(merged);
      final loaded = (await LocalDb.instance.getConnections())
          .singleWhere((c) => c.id == id);
      expect(loaded.password, 'keep-me');
      expect(loaded.name, 'PG Renamed');
    });
  });
}
