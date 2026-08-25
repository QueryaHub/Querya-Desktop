import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// SQLite database connection using sqflite_common_ffi.
class SqliteConnection {
  SqliteConnection({
    required this.id,
    required this.name,
    required this.path,
    this.readOnly = false,
  });

  factory SqliteConnection.fromConnectionRow(
    ConnectionRow row, {
    bool? readOnly,
  }) {
    return SqliteConnection(
      id: row.id ?? 0,
      name: row.name,
      path: row.host ?? '', // Store absolute file path in the 'host' field
      readOnly: readOnly ?? row.useSSL, // Store read-only flag in the 'useSSL' field
    );
  }

  final int id;
  final String name;
  final String path;
  final bool readOnly;

  Database? _db;
  bool _isConnected = false;

  bool get isConnected => _isConnected && _db != null;

  Future<void> connect() async {
    if (_isConnected && _db != null) return;
    try {
      await LocalDb.initFfi();
      _db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          readOnly: readOnly,
          onOpen: (db) async {
            if (!readOnly) {
              await db.execute('PRAGMA foreign_keys = ON');
            }
          },
        ),
      );
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      _db = null;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    final d = _db;
    _db = null;
    try {
      await d?.close();
    } catch (e) {
      debugPrint('SqliteConnection.disconnect: $e');
    }
  }

  Future<void> forceClose() => disconnect();

  Future<bool> testConnection() async {
    try {
      await connect();
      if (_db != null) {
        await _db!.rawQuery('SELECT 1');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('SqliteConnection.testConnection: $e');
      return false;
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
    final sqlLower = sql
        .replaceAll(RegExp(r'--.*$', multiLine: true), '')
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .trim()
        .toLowerCase();
    
    // SQLite can execute PRAGMA, SELECT, EXPLAIN statements, which return data
    final isReadOnlyQuery = sqlLower.startsWith('select') ||
        sqlLower.startsWith('pragma') ||
        sqlLower.startsWith('explain') ||
        sqlLower.startsWith('with') ||
        sqlLower.startsWith('values');

    final hasReturning = RegExp(r'\breturning\b').hasMatch(sqlLower);

    if (readOnly && !isReadOnlyQuery) {
      throw StateError('Database connection is read-only');
    }

    try {
      if (isReadOnlyQuery || hasReturning) {
        return await _db!.rawQuery(sql, arguments);
      } else {
        await _db!.execute(sql, arguments);
        return [];
      }
    } on TimeoutException {
      unawaited(forceClose());
      rethrow;
    }
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
    return rows.map((r) => {
      'name': r['name'] as String,
      'table': r['tbl_name'] as String,
    }).toList();
  }

  /// Lists column names for a table.
  Future<List<String>> listColumnNames({required String table}) async {
    final rows = await execute('PRAGMA table_info(${quoteIdentifier(table)})');
    return rows.map((r) => r['name'] as String).toList();
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
      "SELECT sql FROM sqlite_master WHERE name = :name",
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

    final tblCountRows = await execute("SELECT count(*) AS c FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    final tblCount = (tblCountRows.isNotEmpty ? tblCountRows.first['c'] : 0) ?? 0;

    return {
      'version': ver,
      'page_count': pc,
      'page_size': ps,
      'journal_mode': jm,
      'table_count': tblCount,
    };
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
