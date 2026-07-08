import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
    } catch (_) {}
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
    } catch (_) {
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

    if (isReadOnlyQuery || hasReturning) {
      return await _db!.rawQuery(sql, arguments);
    } else {
      await _db!.execute(sql, arguments);
      return [];
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

  /// Helper to quote SQLite identifiers safely.
  static String quoteIdentifier(String id) {
    return '"${id.replaceAll('"', '""')}"';
  }
}
