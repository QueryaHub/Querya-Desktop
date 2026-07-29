import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'querya.db';
const _dbVersion = 8;

/// Fallback when [recordSqlQueryHistory] is called without `maxEntries`.
/// Keep in sync with [kDefaultSqlHistoryMaxEntries] in `app_settings.dart`.
const int kDefaultSqlHistoryCap = 100;

int? _sqliteInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? _normalizeHistoryDatabaseName(String? databaseName) {
  final t = databaseName?.trim();
  if (t == null || t.isEmpty) return null;
  return t;
}

/// Local SQLite database for folders and connections.
/// File: [applicationSupport]/querya_desktop/querya.db
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;
  String? _cachedDbPath;

  static Future<void> initFfi() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
    }
  }

  Future<Database> _open() async {
    if (_db != null && _db!.isOpen) return _db!;
    await initFfi();
    if (_cachedDbPath == null) {
      final dir = await AppDataRoot.applicationSupportDirectory();
      final sub = Directory(p.join(dir.path, 'querya_desktop'));
      if (!await sub.exists()) await sub.create(recursive: true);
      _cachedDbPath = p.join(sub.path, _dbName);
    }
    _db = await databaseFactoryFfi.openDatabase(
      _cachedDbPath!,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE connections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        host TEXT,
        port INTEGER,
        username TEXT,
        password TEXT,
        database_name TEXT,
        auth_source TEXT,
        use_ssl INTEGER NOT NULL DEFAULT 0,
        connection_string TEXT,
        extension_id TEXT,
        driver_options TEXT,
        folder_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sql_query_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        connection_id INTEGER NOT NULL REFERENCES connections(id) ON DELETE CASCADE,
        database_name TEXT,
        sql_text TEXT NOT NULL,
        recorded_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_sql_query_history_lookup
      ON sql_query_history (connection_id, database_name, recorded_at DESC, id DESC)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE connections ADD COLUMN password TEXT');
      await db.execute('ALTER TABLE connections ADD COLUMN database_name TEXT');
      await db.execute('ALTER TABLE connections ADD COLUMN auth_source TEXT');
      await db.execute(
          'ALTER TABLE connections ADD COLUMN use_ssl INTEGER NOT NULL DEFAULT 0');
      await db
          .execute('ALTER TABLE connections ADD COLUMN connection_string TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('PRAGMA foreign_keys=ON');
      await db.execute('''
        CREATE TABLE connections_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          name TEXT NOT NULL,
          host TEXT,
          port INTEGER,
          username TEXT,
          password TEXT,
          database_name TEXT,
          auth_source TEXT,
          use_ssl INTEGER NOT NULL DEFAULT 0,
          connection_string TEXT,
          folder_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        INSERT INTO connections_new 
        SELECT id, type, name, host, port, username, password, database_name, 
               auth_source, use_ssl, connection_string, folder_id, sort_order, created_at 
        FROM connections
      ''');
      await db.execute('DROP TABLE connections');
      await db.execute('ALTER TABLE connections_new RENAME TO connections');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE app_settings (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 5) {
      final rows = await db.query('connections');
      for (final m in rows) {
        final id = _sqliteInt(m['id']);
        if (id == null) continue;
        final pwd = m['password'] as String?;
        final cs = m['connection_string'] as String?;
        await ConnectionSecretsStore.writeForConnection(
          id,
          password: (pwd != null && pwd.isNotEmpty) ? pwd : null,
          connectionString: (cs != null && cs.isNotEmpty) ? cs : null,
        );
      }
      await db.execute(
        'UPDATE connections SET password = NULL, connection_string = NULL',
      );
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE sql_query_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          connection_id INTEGER NOT NULL REFERENCES connections(id) ON DELETE CASCADE,
          database_name TEXT,
          sql_text TEXT NOT NULL,
          recorded_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE INDEX idx_sql_query_history_lookup
        ON sql_query_history (connection_id, recorded_at DESC)
      ''');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE connections ADD COLUMN extension_id TEXT');
      await db
          .execute('ALTER TABLE connections ADD COLUMN driver_options TEXT');
    }
    if (oldVersion < 8) {
      await db.execute('DROP INDEX IF EXISTS idx_sql_query_history_lookup');
      await db.execute('''
        CREATE INDEX idx_sql_query_history_lookup
        ON sql_query_history (connection_id, database_name, recorded_at DESC, id DESC)
      ''');
    }
  }

  Future<String?> getAppSetting(String key) async {
    final db = await _open();
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setAppSetting(String key, String value) async {
    final db = await _open();
    await db.rawInsert(
      'INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)',
      [key, value],
    );
  }

  Future<void> deleteAppSetting(String key) async {
    final db = await _open();
    await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  final Map<String, int> _historyInsertCounts = {};

  Future<void> recordSqlQueryHistory({
    required int connectionId,
    String? databaseName,
    required String sqlText,
    int maxEntries = kDefaultSqlHistoryCap,
    bool forcePrune = false,
  }) async {
    final sql = sqlText.trim();
    if (sql.isEmpty) return;
    if (maxEntries < 1) return;
    final db = await _open();
    final dbKey = _normalizeHistoryDatabaseName(databaseName);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('sql_query_history', {
      'connection_id': connectionId,
      'database_name': dbKey,
      'sql_text': sql,
      'recorded_at': now,
    });

    final bucketKey = '$connectionId::${dbKey ?? ''}';
    final insertCount = (_historyInsertCounts[bucketKey] ?? 0) + 1;
    _historyInsertCounts[bucketKey] = insertCount;

    final batchThreshold = maxEntries <= 10 ? 1 : 10;
    if (forcePrune || insertCount >= batchThreshold) {
      _historyInsertCounts[bucketKey] = 0;
      await _pruneSqlQueryHistoryBucket(
        db,
        connectionId: connectionId,
        databaseName: dbKey,
        maxEntries: maxEntries,
      );
    }
  }

  /// Keeps the newest [maxEntries] rows in a (connection, database) bucket.
  ///
  /// Selects overflow ids (oldest first), then deletes by primary key — avoids
  /// nested `DELETE … SELECT … OFFSET` plans as history grows.
  Future<void> _pruneSqlQueryHistoryBucket(
    Database db, {
    required int connectionId,
    required String? databaseName,
    required int maxEntries,
  }) async {
    final countRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM sql_query_history
      WHERE connection_id = ? AND database_name IS NOT DISTINCT FROM ?
      ''',
      [connectionId, databaseName],
    );
    final count = _sqliteInt(countRows.first['c']) ?? 0;
    final excess = count - maxEntries;
    if (excess <= 0) return;

    final overflow = await db.rawQuery(
      '''
      SELECT id FROM sql_query_history
      WHERE connection_id = ? AND database_name IS NOT DISTINCT FROM ?
      ORDER BY recorded_at ASC, id ASC
      LIMIT ?
      ''',
      [connectionId, databaseName, excess],
    );
    if (overflow.isEmpty) return;

    final ids = <Object>[];
    for (final row in overflow) {
      final id = row['id'];
      if (id != null) ids.add(id);
    }
    if (ids.isEmpty) return;

    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawDelete(
      'DELETE FROM sql_query_history WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<List<SqlQueryHistoryEntry>> listSqlQueryHistory({
    required int connectionId,
    String? databaseName,
    int limit = 50,
  }) async {
    final db = await _open();
    final dbKey = _normalizeHistoryDatabaseName(databaseName);
    final rows = await db.rawQuery(
      '''
      SELECT id, connection_id, database_name, sql_text, recorded_at
      FROM sql_query_history
      WHERE connection_id = ? AND database_name IS NOT DISTINCT FROM ?
      ORDER BY recorded_at DESC, id DESC
      LIMIT ?
      ''',
      [connectionId, dbKey, limit],
    );
    return rows.map(SqlQueryHistoryEntry.fromMap).toList();
  }

  /// Removes all history rows for [connectionId] (every database bucket).
  Future<void> clearSqlQueryHistoryForConnection(int connectionId) async {
    final db = await _open();
    await db.delete(
      'sql_query_history',
      where: 'connection_id = ?',
      whereArgs: [connectionId],
    );
  }

  /// Removes history for [connectionId] and [databaseName] only (same bucket as [listSqlQueryHistory]).
  Future<void> clearSqlQueryHistoryBucket({
    required int connectionId,
    String? databaseName,
  }) async {
    final db = await _open();
    final dbKey = _normalizeHistoryDatabaseName(databaseName);
    await db.rawDelete(
      '''
      DELETE FROM sql_query_history
      WHERE connection_id = ? AND database_name IS NOT DISTINCT FROM ?
      ''',
      [connectionId, dbKey],
    );
  }

  Future<List<String>> getFolders() async {
    final db = await _open();
    final rows = await db.query('folders', orderBy: 'sort_order ASC, name ASC');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> addFolder(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final db = await _open();
    await db.insert('folders', {'name': n});
  }

  Future<void> removeFolder(String name) async {
    final db = await _open();
    await db.delete('folders', where: 'name = ?', whereArgs: [name]);
  }

  Future<void> clearFolders() async {
    final db = await _open();
    await db.delete('folders');
  }

  Future<int?> getFolderIdByName(String name) async {
    final db = await _open();
    final rows = await db.query('folders',
        columns: ['id'], where: 'name = ?', whereArgs: [name]);
    if (rows.isEmpty) return null;
    return _sqliteInt(rows.first['id']);
  }

  Future<List<ConnectionRow>> getConnections() async {
    final db = await _open();
    final rows =
        await db.query('connections', orderBy: 'sort_order ASC, name ASC');
    final futures =
        rows.map((m) => _hydrateConnection(ConnectionRow.fromMap(m)));
    return Future.wait(futures);
  }

  static Future<ConnectionRow> _hydrateConnection(ConnectionRow row) async {
    if (row.id == null) return row;
    final secrets = await ConnectionSecretsStore.readForConnection(row.id!);
    return ConnectionRow(
      id: row.id,
      type: row.type,
      name: row.name,
      host: row.host,
      port: row.port,
      username: row.username,
      password: secrets.password ?? row.password,
      databaseName: row.databaseName,
      authSource: row.authSource,
      useSSL: row.useSSL,
      connectionString: secrets.connectionString ?? row.connectionString,
      folderId: row.folderId,
      sortOrder: row.sortOrder,
      createdAt: row.createdAt,
    );
  }

  /// Inserts a row and returns the SQLite row id.
  /// Password and connection string are stored in the OS secure store, not in SQLite.
  ///
  /// If writing secrets fails, the SQLite row is rolled back and the error is
  /// rethrown so callers can surface a Keychain / libsecret failure.
  Future<int> addConnection(ConnectionRow row) async {
    final db = await _open();
    final id = await db.insert('connections', row.toPersistenceMap());
    try {
      await ConnectionSecretsStore.writeForConnection(
        id,
        password: row.password,
        connectionString: row.connectionString,
      );
    } catch (e) {
      try {
        await ConnectionSecretsStore.deleteForConnection(id);
      } catch (_) {
        // Best-effort cleanup of any partial secret writes.
      }
      await db.delete('connections', where: 'id = ?', whereArgs: [id]);
      rethrow;
    }
    return id;
  }

  /// Updates an existing connection row in SQLite and its secrets in the secure store.
  ///
  /// If writing secrets fails, the previous SQLite row and previous secrets are
  /// restored (best effort) and the error is rethrown.
  Future<void> updateConnection(ConnectionRow row) async {
    if (row.id == null) {
      throw ArgumentError(
          'ConnectionRow.id cannot be null when calling updateConnection');
    }
    final db = await _open();
    final previousMaps = await db.query(
      'connections',
      where: 'id = ?',
      whereArgs: [row.id],
    );
    if (previousMaps.isEmpty) {
      throw ArgumentError('No connection found with id ${row.id}');
    }
    final previousRow = ConnectionRow.fromMap(previousMaps.first);
    final previousSecrets =
        await ConnectionSecretsStore.readForConnection(row.id!);

    await db.transaction((txn) async {
      final count = await txn.update(
        'connections',
        row.toPersistenceMap(),
        where: 'id = ?',
        whereArgs: [row.id],
      );
      if (count == 0) {
        throw ArgumentError('No connection found with id ${row.id}');
      }
    });

    try {
      await ConnectionSecretsStore.writeForConnection(
        row.id!,
        password: row.password,
        connectionString: row.connectionString,
      );
    } catch (e) {
      await db.update(
        'connections',
        previousRow.toPersistenceMap(),
        where: 'id = ?',
        whereArgs: [row.id],
      );
      try {
        await ConnectionSecretsStore.writeForConnection(
          row.id!,
          password: previousSecrets.password,
          connectionString: previousSecrets.connectionString,
        );
      } catch (_) {
        // Best-effort restore of previous secrets; surface the original error.
      }
      rethrow;
    }
  }

  /// Deletes a connection. SQLite deletion always proceeds even if the secure
  /// store delete fails (e.g. missing key or unavailable libsecret daemon).
  Future<void> removeConnection(int id) async {
    try {
      await ConnectionSecretsStore.deleteForConnection(id);
    } catch (_) {
      // Do not block removing the connection metadata when the OS store fails.
    }
    final db = await _open();
    await db.delete('connections', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _cachedDbPath = null;
  }
}

/// One row from [LocalDb.sql_query_history] (recent SQL, no secrets).
class SqlQueryHistoryEntry {
  const SqlQueryHistoryEntry({
    required this.id,
    required this.connectionId,
    this.databaseName,
    required this.sqlText,
    required this.recordedAt,
  });

  final int id;
  final int connectionId;
  final String? databaseName;
  final String sqlText;
  final String recordedAt;

  static SqlQueryHistoryEntry fromMap(Map<String, Object?> m) =>
      SqlQueryHistoryEntry(
        id: _sqliteInt(m['id'])!,
        connectionId: _sqliteInt(m['connection_id'])!,
        databaseName: m['database_name'] as String?,
        sqlText: m['sql_text'] as String,
        recordedAt: m['recorded_at'] as String,
      );
}

class ConnectionRow {
  const ConnectionRow({
    this.id,
    required this.type,
    required this.name,
    this.host,
    this.port,
    this.username,
    this.password,
    this.databaseName,
    this.authSource,
    this.useSSL = false,
    this.connectionString,
    this.extensionId,
    this.driverOptions,
    this.folderId,
    this.sortOrder = 0,
    required this.createdAt,
  });

  final int? id;
  final String type;
  final String name;
  final String? host;
  final int? port;
  final String? username;
  final String? password;
  final String? databaseName;
  final String? authSource;
  final bool useSSL;
  final String? connectionString;

  /// Package id of an installed extension driver (null for built-ins).
  final String? extensionId;

  /// Non-secret driver-specific form values as JSON text.
  final String? driverOptions;

  final int? folderId;
  final int sortOrder;
  final String createdAt;

  /// True when this row is backed by an installed extension driver.
  bool get isExtensionDriver =>
      extensionId != null && extensionId!.trim().isNotEmpty;

  Map<String, Object?> toMap() => {
        'type': type,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'database_name': databaseName,
        'auth_source': authSource,
        'use_ssl': useSSL ? 1 : 0,
        'connection_string': connectionString,
        'extension_id': extensionId,
        'driver_options': driverOptions,
        'folder_id': folderId,
        'sort_order': sortOrder,
        'created_at': createdAt,
      };

  /// SQLite row without secrets ([password], [connectionString]); use the secure store for those.
  Map<String, Object?> toPersistenceMap() => {
        'type': type,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': null,
        'database_name': databaseName,
        'auth_source': authSource,
        'use_ssl': useSSL ? 1 : 0,
        'connection_string': null,
        'extension_id': extensionId,
        'driver_options': driverOptions,
        'folder_id': folderId,
        'sort_order': sortOrder,
        'created_at': createdAt,
      };

  static ConnectionRow fromMap(Map<String, Object?> m) => ConnectionRow(
        id: _sqliteInt(m['id']),
        type: m['type'] as String,
        name: m['name'] as String,
        host: m['host'] as String?,
        port: _sqliteInt(m['port']),
        username: m['username'] as String?,
        password: m['password'] as String?,
        databaseName: m['database_name'] as String?,
        authSource: m['auth_source'] as String?,
        useSSL: _sqliteInt(m['use_ssl']) == 1,
        connectionString: m['connection_string'] as String?,
        extensionId: m['extension_id'] as String?,
        driverOptions: m['driver_options'] as String?,
        folderId: _sqliteInt(m['folder_id']),
        sortOrder: _sqliteInt(m['sort_order']) ?? 0,
        createdAt: m['created_at'] as String,
      );

  ConnectionRow copyWith({
    int? id,
    String? type,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? databaseName,
    String? authSource,
    bool? useSSL,
    String? connectionString,
    String? extensionId,
    String? driverOptions,
    int? folderId,
    int? sortOrder,
    String? createdAt,
    bool clearPassword = false,
    bool clearConnectionString = false,
  }) {
    return ConnectionRow(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: clearPassword ? null : (password ?? this.password),
      databaseName: databaseName ?? this.databaseName,
      authSource: authSource ?? this.authSource,
      useSSL: useSSL ?? this.useSSL,
      connectionString: clearConnectionString
          ? null
          : (connectionString ?? this.connectionString),
      extensionId: extensionId ?? this.extensionId,
      driverOptions: driverOptions ?? this.driverOptions,
      folderId: folderId ?? this.folderId,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
