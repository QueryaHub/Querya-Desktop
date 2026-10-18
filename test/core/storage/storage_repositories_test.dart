import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/activity_log_repository.dart';
import 'package:querya_desktop/core/storage/app_settings_repository.dart';
import 'package:querya_desktop/core/storage/folder_repository.dart';
import 'package:querya_desktop/core/storage/local_db_models.dart';
import 'package:querya_desktop/core/storage/local_db_schema.dart';
import 'package:querya_desktop/core/storage/sql_query_history_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The repositories on a database of their own (in memory, made by
/// [LocalDbSchema]), without [LocalDb] (#1502).
void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: LocalDbSchema.version,
        onCreate: LocalDbSchema.onCreate,
        onOpen: LocalDbSchema.onOpen,
      ),
    );
  });
  tearDown(() => db.close());

  Future<Database> open() async => db;

  Future<int> insertConnection({int? folderId}) => db.insert('connections', {
        'type': 'sqlite',
        'name': 'c',
        'folder_id': folderId,
        'created_at': '2026-10-18',
      });

  test('folders: added in order, removed without taking their connections',
      () async {
    final folders = FolderRepository(open);
    await folders.addFolder('  work  ');
    await folders.addFolder('home');
    await folders.addFolder('   ');
    expect(await folders.getFolders(), ['home', 'work']);

    final workId = await folders.getFolderIdByName('work');
    expect(workId, isNotNull);
    final conn = await insertConnection(folderId: workId);
    await folders.removeFolder('work');
    expect(await folders.getFolders(), ['home']);
    final rows = await db.query('connections', where: 'id = ?', whereArgs: [conn]);
    expect(rows.single['folder_id'], isNull);
  });

  test('app settings: set, replace, delete and ER layouts per scope', () async {
    final settings = AppSettingsRepository(open);
    expect(await settings.getAppSetting('k'), isNull);
    await settings.setAppSetting('k', 'v1');
    await settings.setAppSetting('k', 'v2');
    expect(await settings.getAppSetting('k'), 'v2');
    await settings.deleteAppSetting('k');
    expect(await settings.getAppSetting('k'), isNull);

    final conn = await insertConnection();
    await settings.writeErdLayout(conn, 'public', '{"a":1}');
    await settings.writeErdLayout(conn, 'other', '{"b":2}');
    await settings.writeErdLayout(conn, 'public', '{"a":3}');
    expect(await settings.readErdLayout(conn, 'public'), '{"a":3}');
    expect(await settings.readErdLayout(conn, 'other'), '{"b":2}');
    expect(await settings.readErdLayout(conn, 'none'), isNull);
  });

  test('query history: newest first, capped per bucket, cleared by bucket',
      () async {
    final history = SqlQueryHistoryRepository(open);
    final conn = await insertConnection();
    for (var i = 0; i < 5; i++) {
      await history.recordSqlQueryHistory(
        connectionId: conn,
        databaseName: 'db',
        sqlText: 'SELECT $i',
        maxEntries: 3,
        forcePrune: true,
      );
    }
    await history.recordSqlQueryHistory(
      connectionId: conn,
      databaseName: 'other',
      sqlText: 'SELECT other',
      maxEntries: 3,
    );
    final db1 = await history.listSqlQueryHistory(
        connectionId: conn, databaseName: 'db');
    expect([for (final e in db1) e.sqlText], ['SELECT 4', 'SELECT 3', 'SELECT 2']);

    await history.clearSqlQueryHistoryBucket(
        connectionId: conn, databaseName: 'db');
    expect(
        await history.listSqlQueryHistory(
            connectionId: conn, databaseName: 'db'),
        isEmpty);
    expect(
        await history.listSqlQueryHistory(
            connectionId: conn, databaseName: 'other'),
        hasLength(1));
  });

  test('activity log: MCP calls are listed newest first and clearable',
      () async {
    final log = ActivityLogRepository(open);
    expect(await log.listMcpActivity(), isEmpty);
    for (final tool in ['list_tables', 'run_query']) {
      await log.recordMcpActivity(McpActivityEntry(
        recordedAt: DateTime.now().toUtc().toIso8601String(),
        client: 'test',
        tool: tool,
        durationMs: 3,
        refusalRule: tool == 'run_query' ? 'read_only_only' : null,
      ));
    }
    final entries = await log.listMcpActivity();
    expect([for (final e in entries) e.tool], ['run_query', 'list_tables']);
    expect(entries.first.refusalRule, 'read_only_only');
    await log.clearMcpActivity();
    expect(await log.listMcpActivity(), isEmpty);
  });
}
