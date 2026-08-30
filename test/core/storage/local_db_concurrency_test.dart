import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

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
    tempDir = await Directory.systemTemp.createTemp('querya_local_db_concurrency_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalDb concurrency and PRAGMA settings', () {
    test('enables WAL journal mode, busy_timeout, and normal synchronous', () async {
      final foreignKeys = await LocalDb.instance.getPragma('foreign_keys');
      expect(foreignKeys, equals('1'));

      final journalMode = await LocalDb.instance.getPragma('journal_mode');
      expect(journalMode.toLowerCase(), equals('wal'));

      final busyTimeout = await LocalDb.instance.getPragma('busy_timeout');
      expect(busyTimeout, equals('5000'));

      final synchronous = await LocalDb.instance.getPragma('synchronous');
      // In SQLite, synchronous = NORMAL corresponds to integer 1
      expect(synchronous, equals('1'));
    });

    test('handles concurrent reads and writes gracefully without lock errors', () async {
      // Create folder and connection
      await LocalDb.instance.addFolder('Concurrency Test Folder');
      final folders = await LocalDb.instance.getFolders();
      expect(folders, contains('Concurrency Test Folder'));

      final connId = await LocalDb.instance.addConnection(
        ConnectionRow(
          type: 'postgresql',
          name: 'Concurrency Test Postgres',
          host: 'localhost',
          port: 5432,
          username: 'querya',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      // Fire 20 parallel inserts and reads concurrently
      final futures = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        futures.add(
          LocalDb.instance.recordSqlQueryHistory(
            connectionId: connId,
            databaseName: 'test_db',
            sqlText: 'SELECT * FROM items WHERE id = $i;',
          ),
        );
        futures.add(
          LocalDb.instance.listSqlQueryHistory(
            connectionId: connId,
            databaseName: 'test_db',
          ).then((_) {}),
        );
      }

      await expectLater(Future.wait(futures), completes);

      final history = await LocalDb.instance.listSqlQueryHistory(
        connectionId: connId,
        databaseName: 'test_db',
        limit: 100,
      );
      expect(history.length, equals(20));

      // Cleanup
      await LocalDb.instance.removeConnection(connId);
      await LocalDb.instance.removeFolder('Concurrency Test Folder');
    });

    test('deduplicates parallel cold-start open calls via single-flight memoization', () async {
      // Close database to simulate completely cold state
      await LocalDb.instance.close();

      // Launch multiple simultaneous queries on a closed database
      final parallelOperations = [
        LocalDb.instance.getFolders(),
        LocalDb.instance.getConnections(),
        LocalDb.instance.getAppSetting('theme_preset'),
        LocalDb.instance.getPragma('journal_mode'),
      ];

      final results = await Future.wait(parallelOperations);
      expect(results[0], isA<List<String>>());
      expect(results[1], isA<List<ConnectionRow>>());
      expect(results[3].toString().toLowerCase(), equals('wal'));
    });
  });
}
