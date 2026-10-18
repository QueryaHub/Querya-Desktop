import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/local_db_test_support.dart';

/// A database written by a newer Querya is refused and left as it is (#1497).
void main() {
  late Directory dir;

  setUpAll(() async => dir = await initTestLocalDb('newer_schema_'));
  tearDownAll(() => disposeTestLocalDb(dir));

  Future<int> versionOnDisk(String path) async {
    final raw = await databaseFactoryFfi.openDatabase(path);
    try {
      return await raw.getVersion();
    } finally {
      await raw.close();
    }
  }

  test('a backup before an update, then the database opens again', () async {
    final db = LocalDb.instance;
    await db.setAppSetting('before_update', 'yes');

    final copy = await db.backupBeforeUpdate(
      fromVersion: '0.4.22',
      toVersion: '0.5.0-beta.1',
    );

    expect(File(copy).existsSync(), isTrue);
    expect(copy, endsWith('querya.db.pre-0.4.22-0.5.0-beta.1.bak'));
    expect(await db.getAppSetting('before_update'), 'yes');
  });

  test('a newer schema version is refused and not overwritten', () async {
    final db = LocalDb.instance;
    final path = await db.databasePath();
    final current = await versionOnDisk(path);
    await db.close();

    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.setVersion(current + 7);
    await raw.close();

    await expectLater(
      db.open(),
      throwsA(isA<LocalDbNewerSchemaException>()
          .having((e) => e.found, 'found', current + 7)
          .having((e) => e.supported, 'supported', current)
          .having((e) => e.toString(), 'message', contains('newer version'))),
    );
    expect(await versionOnDisk(path), current + 7, reason: 'left as it was');

    // Back to the version this build knows, for the other tests.
    final fix = await databaseFactoryFfi.openDatabase(path);
    await fix.setVersion(current);
    await fix.close();
    expect(await db.getAppSetting('before_update'), 'yes');
  });
}
