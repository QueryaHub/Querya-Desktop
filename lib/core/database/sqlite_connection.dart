import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';
import 'package:querya_desktop/core/database/sqlite_sql.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// In-memory paths (`:memory:`) skip the missing-file check.
bool sqlitePathIsInMemory(String path) =>
    path == inMemoryDatabasePath || path == ':memory:';

/// Maps driver / OS errors to a user-facing [SqliteConnectionException].
SqliteConnectionException sqliteMapOpenError(Object error, String path) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('not found') ||
      msg.contains('no such file') ||
      msg.contains('errno = 2') ||
      msg.contains('errno =2')) {
    return SqliteConnectionException(
      'SQLite file not found: $path',
      cause: error,
    );
  }
  if (msg.contains('permission') ||
      msg.contains('access denied') ||
      msg.contains('errno = 13') ||
      msg.contains('errno =13')) {
    return SqliteConnectionException(
      'Permission denied opening SQLite file: $path',
      cause: error,
    );
  }
  if (msg.contains('not a database') ||
      msg.contains('malformed') ||
      msg.contains('corrupt') ||
      msg.contains('disk image')) {
    return SqliteConnectionException(
      'SQLite database is corrupt or not a database: $path',
      cause: error,
    );
  }
  return SqliteConnectionException(
    'Failed to open SQLite database: $error',
    cause: error,
  );
}

/// SQLite database connection using sqflite_common_ffi.
class SqliteConnection {
  SqliteConnection({
    required this.id,
    required this.name,
    required this.path,
    this.readOnly = false,
    this.createIfMissing = false,
  });

  factory SqliteConnection.fromConnectionRow(
    ConnectionRow row, {
    bool? readOnly,
  }) {
    return SqliteConnection(
      id: row.id ?? 0,
      name: row.name,
      path: row.host ?? '', // Store absolute file path in the 'host' field
      readOnly:
          readOnly ?? row.useSSL, // Store read-only flag in the 'useSSL' field
    );
  }

  final int id;
  final String name;
  final String path;
  final bool readOnly;

  /// When true, `openDatabase` may create the file (new-connection Save only).
  final bool createIfMissing;

  Database? _db;
  bool _isConnected = false;
  bool _inTransaction = false;

  bool get isConnected => _isConnected && _db != null;

  Future<void> connect() async {
    if (_isConnected && _db != null) return;
    try {
      await LocalDb.initFfi();
      _ensureFileReady();
      _db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          readOnly: readOnly,
          // Every SqliteConnection needs its own handle. With the sqflite
          // default (singleInstance: true) a second open of the same path
          // returns the first Database: a Save session would reuse a
          // read-only browse handle, and closing any pooled session would
          // close the file for every other session too.
          singleInstance: false,
          onOpen: (db) async {
            await db.execute('PRAGMA busy_timeout = 5000');
            await db.rawQuery('SELECT 1');
            if (!readOnly) {
              await db.execute('PRAGMA foreign_keys = ON');
              try {
                await db.execute('PRAGMA journal_mode = WAL');
              } catch (e) {
                debugPrint('SqliteConnection WAL not available: $e');
              }
            }
          },
        ),
      );
      _isConnected = true;
    } on SqliteConnectionException {
      _isConnected = false;
      _db = null;
      rethrow;
    } catch (e) {
      _isConnected = false;
      _db = null;
      throw sqliteMapOpenError(e, path);
    }
  }

  void _ensureFileReady() {
    if (sqlitePathIsInMemory(path)) return;
    final file = File(path);
    if (file.existsSync()) {
      if (file.statSync().type == FileSystemEntityType.directory) {
        throw SqliteConnectionException('SQLite path is a directory: $path');
      }
      return;
    }
    // sqflite FFI uses OpenMode.readWriteCreate and even mkdir's parents.
    if (!createIfMissing || readOnly) {
      throw SqliteConnectionException('SQLite file not found: $path');
    }
  }

  /// Creates an empty SQLite file if [path] is missing (new-connection Save).
  static Future<void> createFileIfMissing(String path) async {
    if (sqlitePathIsInMemory(path)) return;
    if (File(path).existsSync()) return;
    final conn = SqliteConnection(
      id: 0,
      name: 'create',
      path: path,
      createIfMissing: true,
    );
    try {
      await conn.connect();
    } finally {
      await conn.disconnect();
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _inTransaction = false;
    final d = _db;
    _db = null;
    try {
      await d?.close();
    } catch (e) {
      debugPrint('SqliteConnection.disconnect: $e');
    }
  }

  Future<void> forceClose() => disconnect();

  /// Tests connectivity without leaving a session open.
  Future<({bool ok, String? error})> testConnection() async {
    try {
      await connect();
      if (_db != null) {
        await _db!.rawQuery('SELECT 1');
        return (ok: true, error: null);
      }
      return (ok: false, error: 'Connection could not be established.');
    } on SqliteConnectionException catch (e) {
      return (ok: false, error: e.message);
    } catch (e) {
      return (ok: false, error: sqliteMapOpenError(e, path).message);
    } finally {
      await disconnect();
    }
  }

  /// Runs SQL on SQLite. If read-only, only query statements are allowed.
  Future<List<Map<String, Object?>>> execute(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (!isConnected || _db == null) {
      throw StateError('Not connected to SQLite');
    }
    final sqlLower = sqliteStripSqlComments(sql).trim().toLowerCase();
    final isReadOnlyQuery = sqliteSqlIsReadOnlyQuery(sql);

    final hasReturning = RegExp(r'\breturning\b').hasMatch(sqlLower);

    if (readOnly && !isReadOnlyQuery) {
      throw StateError('Database connection is read-only');
    }

    try {
      if (isReadOnlyQuery || hasReturning) {
        return await _db!.rawQuery(sql, arguments);
      } else {
        await _db!.execute(sql, arguments);
        _noteTransactionSql(sqlLower);
        return [];
      }
    } on TimeoutException {
      unawaited(forceClose());
      rethrow;
    } on DatabaseException catch (e) {
      if (_isSqliteBusy(e)) {
        throw StateError(
          'SQLite is busy (another connection is writing). Retry in a moment.',
        );
      }
      rethrow;
    }
  }

  /// Runs DML and returns sqlite `changes()` for the last INSERT/UPDATE/DELETE.
  Future<int> executeAffected(String sql) async {
    await execute(sql);
    if (!isConnected || _db == null) return 0;
    final rows = await _db!.rawQuery('SELECT changes() AS c');
    if (rows.isEmpty) return 0;
    final v = rows.first['c'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  /// Runs [execute] with an application-level [timeout].
  Future<List<Map<String, Object?>>> executeWithTimeout(
    String sql, {
    Duration? timeout,
    List<Object?>? arguments,
  }) async {
    final f = execute(sql, arguments);
    if (timeout == null) return f;
    try {
      return await f.timeout(timeout);
    } on TimeoutException {
      unawaited(forceClose());
      rethrow;
    }
  }

  /// Whether this session has an open `BEGIN` (tracked from executed SQL).
  Future<bool?> inOpenTransaction() async {
    if (!isConnected) return null;
    return _inTransaction;
  }

  /// Runs [body] inside a transaction. If the session already has a `BEGIN`,
  /// DML joins it instead of nesting `BEGIN TRANSACTION`.
  Future<void> runInTransaction(Future<void> Function() body) async {
    final join = _inTransaction;
    if (!join) {
      await execute('BEGIN TRANSACTION');
    }
    try {
      await body();
      if (!join) await execute('COMMIT');
    } catch (e) {
      if (!join) {
        try {
          await execute('ROLLBACK');
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Lists tables in the database.
  Future<List<String>> listTables() async {
    final rows = await execute(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Lists views in the database.
  Future<List<String>> listViews() async {
    final rows = await execute(
      "SELECT name FROM sqlite_master WHERE type = 'view' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Lists indexes in the database.
  Future<List<Map<String, String>>> listIndexes() async {
    final rows = await execute(
      "SELECT name, tbl_name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return rows
        .map((r) => {
              'name': r['name'] as String,
              'table': r['tbl_name'] as String,
            })
        .toList();
  }

  /// Lists column names for a table.
  Future<List<String>> listColumnNames({required String table}) async {
    final rows = await execute('PRAGMA table_info(${quoteIdentifier(table)})');
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Attempts to infer column names for a query (even when it yields zero rows)
  /// using an ephemeral TEMP VIEW, or falling back to single-table schema.
  Future<List<String>> inferQueryColumns(String sql) async {
    if (!isConnected || _db == null) return const [];
    final trimmed = sqliteStripSqlComments(sql).trim();
    if (trimmed.isEmpty) return const [];

    // 1. Try temporary view probe in SQLite's in-memory temp schema.
    const viewName = '_querya_zero_row_col_probe';
    try {
      var cleanSql = trimmed;
      while (cleanSql.endsWith(';')) {
        cleanSql = cleanSql.substring(0, cleanSql.length - 1).trim();
      }
      // Note: We execute on _db! directly to bypass readOnly restriction,
      // as temp views only touch in-memory session temp schema.
      await _db!.execute('CREATE TEMP VIEW IF NOT EXISTS $viewName AS $cleanSql');
      final rows = await _db!.rawQuery('PRAGMA table_info($viewName)');
      final cols = rows
          .map((r) => r['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      await _db!.execute('DROP VIEW IF EXISTS $viewName');
      if (cols.isNotEmpty) {
        return cols;
      }
    } catch (_) {
      try {
        await _db!.execute('DROP VIEW IF EXISTS $viewName');
      } catch (_) {}
    }

    // 2. Fallback: single-table target extraction
    final target = SqlTableTargetExtractor.extract(trimmed);
    if (target != null) {
      try {
        return await listColumnNames(table: target.tableName);
      } catch (_) {}
    }

    return const [];
  }

  /// Retrieves schema metadata and primary keys for [table].
  Future<TableSchemaMeta> getTableSchema({required String table}) async {
    final rows = await execute('PRAGMA table_info(${quoteIdentifier(table)})');
    final columns = <TableColumnMeta>[];
    final pkList = <Map<String, dynamic>>[];

    for (final r in rows) {
      final name = r['name'] as String? ?? '';
      final type = r['type'] as String? ?? '';
      final notNull = (r['notnull'] as int? ?? 0) == 1;
      final pk = r['pk'] as int? ?? 0;
      final dflt = r['dflt_value']?.toString();

      final isPk = pk > 0;
      if (isPk) {
        pkList.add({'name': name, 'pk': pk});
      }

      columns.add(
        TableColumnMeta(
          name: name,
          dataType: type,
          isNullable: !notNull,
          isPrimaryKey: isPk,
          primaryKeyPosition: isPk ? pk : null,
          defaultValue: dflt,
        ),
      );
    }

    pkList.sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
    final primaryKeys = pkList.map((e) => e['name'] as String).toList();

    return TableSchemaMeta(
      tableName: table,
      columns: columns,
      primaryKeys: primaryKeys,
    );
  }

  /// Returns primary key column names for [table].
  Future<List<String>> getPrimaryKeys({required String table}) async {
    final schema = await getTableSchema(table: table);
    return schema.primaryKeys;
  }

  /// Returns the DDL (`sql`) of a table or view from sqlite_master.
  Future<String> getObjectDdl(String objectName) async {
    final rows = await execute(
      'SELECT sql FROM sqlite_master WHERE name = ?',
      [objectName],
    );
    if (rows.isEmpty) return '-- No definition found for $objectName';
    return (rows.first['sql'] as String?) ?? '-- Empty definition';
  }

  /// Returns database overview info (`page_count`, `page_size`, `journal_mode`, version, etc.).
  Future<Map<String, dynamic>> databaseOverview() async {
    final verRows = await execute('SELECT sqlite_version() AS ver');
    final ver = (verRows.isNotEmpty ? verRows.first['ver'] : '') ?? '';

    final pcRows = await execute('PRAGMA page_count');
    final pc = (pcRows.isNotEmpty ? pcRows.first.values.first : 0) ?? 0;

    final psRows = await execute('PRAGMA page_size');
    final ps = (psRows.isNotEmpty ? psRows.first.values.first : 0) ?? 0;

    final jmRows = await execute('PRAGMA journal_mode');
    final jm = (jmRows.isNotEmpty ? jmRows.first.values.first : '') ?? '';

    final tblCountRows = await execute(
        "SELECT count(*) AS c FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    final tblCount =
        (tblCountRows.isNotEmpty ? tblCountRows.first['c'] : 0) ?? 0;

    return {
      'version': ver,
      'page_count': pc,
      'page_size': ps,
      'journal_mode': jm,
      'table_count': tblCount,
    };
  }

  void _noteTransactionSql(String sqlLower) {
    if (sqlLower.startsWith('begin')) {
      _inTransaction = true;
      return;
    }
    if (sqlLower.startsWith('commit') || sqlLower.startsWith('end')) {
      _inTransaction = false;
      return;
    }
    if (sqlLower.startsWith('rollback') &&
        !RegExp(r'^rollback\s+to\b').hasMatch(sqlLower)) {
      _inTransaction = false;
    }
  }

  static bool _isSqliteBusy(DatabaseException e) {
    final code = e.getResultCode();
    if (code == 5 || code == 6) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('database is locked') ||
        msg.contains('database busy') ||
        msg.contains('sqlite_busy');
  }

  /// Helper to quote SQLite identifiers safely.
  static String quoteIdentifier(String id) {
    return '"${id.replaceAll('"', '""')}"';
  }
}

class SqliteConnectionException implements Exception {
  SqliteConnectionException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => message;
}
