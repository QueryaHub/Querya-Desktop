import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/storage/update_backup.dart';

/// Copies of the local database before an in-app update (#1497).
void main() {
  late Directory dir;
  late String dbPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('querya_update_backup_');
    dbPath = p.join(dir.path, 'querya.db');
    File(dbPath).writeAsStringSync('main');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('names the copy after both versions, next to the database', () async {
    final copy = await UpdateBackup.create(
      dbPath: dbPath,
      fromVersion: '0.4.22',
      toVersion: '0.5.0-beta.1',
    );
    expect(copy, p.join(dir.path, 'querya.db.pre-0.4.22-0.5.0-beta.1.bak'));
    expect(File(copy).readAsStringSync(), 'main');
  });

  test('copies the WAL with it, and only when there is one', () async {
    File('$dbPath-wal').writeAsStringSync('wal');
    final copy = await UpdateBackup.create(
      dbPath: dbPath,
      fromVersion: '1.0.0',
      toVersion: '1.0.1',
    );
    expect(File('$copy-wal').readAsStringSync(), 'wal');

    File('$dbPath-wal').deleteSync();
    await UpdateBackup.create(dbPath: dbPath, fromVersion: '1.0.0', toVersion: '1.0.1');
    expect(File('$copy-wal').existsSync(), isFalse, reason: 'stale WAL removed');
  });

  test('keeps the newest three and deletes the rest with their WAL', () async {
    final made = <String>[];
    for (var i = 1; i <= 5; i++) {
      if (i == 2) File('$dbPath-wal').writeAsStringSync('wal');
      if (i == 3) File('$dbPath-wal').deleteSync();
      made.add(await UpdateBackup.create(
        dbPath: dbPath,
        fromVersion: '0.4.$i',
        toVersion: '0.4.${i + 1}',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final kept = (await UpdateBackup.list(dbPath)).map((f) => f.path).toList();
    expect(kept, [made[4], made[3], made[2]]);
    expect(File(made[0]).existsSync(), isFalse);
    expect(File(made[1]).existsSync(), isFalse);
    expect(File('${made[1]}-wal').existsSync(), isFalse);
    expect(File(dbPath).existsSync(), isTrue, reason: 'the database itself stays');
  });

  test('odd characters in a version cannot leave the folder', () {
    expect(
      UpdateBackup.pathFor(dbPath, '../x', '1/2'),
      p.join(dir.path, 'querya.db.pre-.._x-1_2.bak'),
    );
  });

  test('a missing database is an error, not an empty copy', () async {
    File(dbPath).deleteSync();
    await expectLater(
      UpdateBackup.create(dbPath: dbPath, fromVersion: 'a', toVersion: 'b'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
