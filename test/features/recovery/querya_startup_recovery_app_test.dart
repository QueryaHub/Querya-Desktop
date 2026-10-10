import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/recovery/querya_startup_recovery_app.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;
  @override
  Future<String?> getApplicationDocumentsPath() async => _root;
  @override
  Future<String?> getTemporaryPath() async => _root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_recovery_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    AppDataRoot.resetMocks();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalDb disaster recovery operations', () {
    test('backupDatabaseFile creates a timestamped copy of querya.db', () async {
      await LocalDb.instance.close();
      final dbPath = await LocalDb.instance.databasePath();
      final dbFile = File(dbPath);
      await dbFile.parent.create(recursive: true);
      await dbFile.writeAsString('fake sqlite header');

      final backupPath = await LocalDb.instance.backupDatabaseFile();
      expect(await File(backupPath).exists(), isTrue);
      expect(backupPath, contains('.corrupted.'));
      expect(await File(backupPath).readAsString(), 'fake sqlite header');
    });

    test('removeWalAndLockFiles deletes sidecar files', () async {
      final dbPath = await LocalDb.instance.databasePath();
      final walFile = File('$dbPath-wal');
      final shmFile = File('$dbPath-shm');
      final lockFile = File('$dbPath-lock');

      await walFile.writeAsString('wal data');
      await shmFile.writeAsString('shm data');
      await lockFile.writeAsString('lock data');

      await LocalDb.instance.removeWalAndLockFiles();

      expect(await walFile.exists(), isFalse);
      expect(await shmFile.exists(), isFalse);
      expect(await lockFile.exists(), isFalse);
    });

    test('resetDatabaseFile backs up and clears querya.db', () async {
      final dbPath = await LocalDb.instance.databasePath();
      final dbFile = File(dbPath);
      await dbFile.writeAsString('corrupted database body');

      await LocalDb.instance.resetDatabaseFile();

      expect(await dbFile.exists(), isFalse);
    });
  });

  group('QueryaStartupRecoveryApp widget', () {
    testWidgets('renders recovery UI with error message and action buttons',
        (tester) async {
      var retried = false;

      await tester.pumpWidget(
        QueryaStartupRecoveryApp(
          error: 'SqliteException(5): database is locked',
          onRetrySuccess: () {
            retried = true;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Database Recovery'), findsOneWidget);
      expect(find.textContaining('SqliteException(5): database is locked'),
          findsOneWidget);
      expect(find.text('Retry Opening'), findsOneWidget);
      expect(find.text('Unlock Database (Clear WAL)'), findsOneWidget);
      expect(find.text('Export / Backup querya.db'), findsOneWidget);
      expect(find.text('Start in Safe Mode'), findsOneWidget);
    });

    testWidgets('retry callback triggers when database can be opened',
        (tester) async {
      var retried = false;

      // Ensure clean db can be opened
      await LocalDb.instance.close();
      final dbPath = await LocalDb.instance.databasePath();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) await dbFile.delete();

      await tester.pumpWidget(
        QueryaStartupRecoveryApp(
          error: 'Transient startup lock error',
          onRetrySuccess: () {
            retried = true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retry Opening'));
      await tester.pumpAndSettle();

      expect(retried, isTrue);
    });
  });
}
