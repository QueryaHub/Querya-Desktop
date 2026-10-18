import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The schema is created whole for a new install and reached step by step from
/// every older version (#1502).
void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() {
    sqfliteFfiInit();
    dir = Directory.systemTemp.createTempSync('local_db_schema_');
  });
  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String path() => '${dir.path}/schema_${n++}.db';

  Future<Database> open(String file, int version,
      {OnDatabaseCreateFn? onCreate, OnDatabaseVersionChangeFn? onUpgrade}) {
    return databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        onOpen: LocalDbSchema.onOpen,
      ),
    );
  }

  Future<Set<String>> tables(Database db) async => {
        for (final r in await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'"))
          r['name']! as String,
      };

  Future<Set<String>> columns(Database db, String table) async => {
        for (final r in await db.rawQuery('PRAGMA table_info($table)'))
          r['name']! as String,
      };

  const allTables = {
    'folders',
    'connections',
    'app_settings',
    'sql_query_history',
    'mutation_audit',
    'mcp_activity',
    'erd_layouts',
  };

  test('a new database has every table and a profile id', () async {
    final db = await open(path(), LocalDbSchema.version,
        onCreate: LocalDbSchema.onCreate);
    expect(await tables(db), allTables);
    expect(await columns(db, 'connections'),
        containsAll(['extension_id', 'driver_options', 'folder_id']));
    expect(await columns(db, 'mcp_activity'), contains('refusal_rule'));
    final id = await db.query('app_settings',
        where: 'key = ?', whereArgs: [profileIdSettingKey]);
    expect(id.single['value'], isNotEmpty);
    await db.close();
  });

  test('the pragmas of an open are set', () async {
    final db = await open(path(), LocalDbSchema.version,
        onCreate: LocalDbSchema.onCreate);
    expect((await db.rawQuery('PRAGMA foreign_keys')).single.values.single, 1);
    expect(
        (await db.rawQuery('PRAGMA busy_timeout')).single.values.single, 5000);
    await db.close();
  });

  test('version 1 reaches the current schema and keeps its connections',
      () async {
    final file = path();
    final v1 = await open(file, 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE folders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          sort_order INTEGER NOT NULL DEFAULT 0
        )''');
      await db.execute('''
        CREATE TABLE connections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          name TEXT NOT NULL,
          host TEXT,
          port INTEGER,
          username TEXT,
          folder_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )''');
      await db.insert('folders', {'name': 'work'});
      await db.insert('connections', {
        'type': 'postgresql',
        'name': 'prod',
        'host': 'db.example',
        'port': 5432,
        'username': 'app',
        'folder_id': 1,
        'created_at': '2026-01-01',
      });
    });
    await v1.close();

    final db = await open(file, LocalDbSchema.version,
        onUpgrade: LocalDbSchema.onUpgrade);
    expect(await tables(db), allTables);
    expect(await columns(db, 'connections'),
        containsAll(['password', 'use_ssl', 'extension_id', 'driver_options']));
    final rows = await db.query('connections');
    expect(rows.single['name'], 'prod');
    expect(rows.single['host'], 'db.example');
    expect(rows.single['folder_id'], 1);
    expect(await db.getVersion(), LocalDbSchema.version);
    await db.close();
  });

  test('version 11 gains the refusal column and the ER layouts table',
      () async {
    final file = path();
    final v11 = await open(file, 11, onCreate: (db, _) async {
      await LocalDbSchema.onCreate(db, 11);
      await db.execute('DROP TABLE erd_layouts');
      await db.execute('ALTER TABLE mcp_activity DROP COLUMN refusal_rule');
    });
    await v11.close();

    final db = await open(file, LocalDbSchema.version,
        onUpgrade: LocalDbSchema.onUpgrade);
    expect(await columns(db, 'mcp_activity'), contains('refusal_rule'));
    expect(await tables(db), contains('erd_layouts'));
    await db.close();
  });

  test('the profile id is made once and kept', () async {
    final db = await open(path(), LocalDbSchema.version,
        onCreate: LocalDbSchema.onCreate);
    final first = await LocalDbSchema.ensureProfileId(db);
    expect(await LocalDbSchema.ensureProfileId(db), first);
    expect(first, hasLength(32));
    await db.close();
  });
}
