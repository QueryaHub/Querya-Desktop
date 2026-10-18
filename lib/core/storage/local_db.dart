import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db_models.dart';
import 'package:querya_desktop/core/storage/local_db_schema.dart';

export 'package:querya_desktop/core/storage/local_db_models.dart';
import 'package:querya_desktop/core/storage/update_backup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/util/log_ignored.dart';

const _dbName = 'querya.db';

/// Fallback when [recordSqlQueryHistory] is called without `maxEntries`.
/// Keep in sync with [kDefaultSqlHistoryMaxEntries] in `app_settings.dart`.
const int kDefaultSqlHistoryCap = 100;

String? _normalizeHistoryDatabaseName(String? databaseName) {
  final t = databaseName?.trim();
  if (t == null || t.isEmpty) return null;
  return t;
}

/// The local database was written by a newer Querya Desktop: its schema
/// version is above the one this build knows (#1497).
///
/// Opening it would have let sqflite write the older version number into it
/// and carry on with tables it does not understand. The open is refused
/// instead, inside the open transaction, so nothing in the file changes.
class LocalDbNewerSchemaException implements Exception {
  const LocalDbNewerSchemaException({
    required this.found,
    required this.supported,
    required this.path,
  });

  /// Schema version stored in the file.
  final int found;

  /// Highest schema version this build reads.
  final int supported;

  final String path;

  @override
  String toString() =>
      'The local data in $path was written by a newer version of Querya '
      'Desktop (data format $found; this version reads up to $supported). '
      'It has not been changed. Install the newer version again, or restore '
      'a copy made before the update (querya.db.pre-<from>-<to>.bak in the '
      'same folder).';
}

/// Local SQLite database for folders and connections.
/// File: [applicationSupport]/querya_desktop/querya.db
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;
  String? _cachedDbPath;
  Future<Database>? _openFuture;

  static Future<void> initFfi() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
    }
  }

  Future<Database> _open() async {
    if (_db != null && _db!.isOpen) return _db!;
    if (_openFuture != null) return _openFuture!;

    final future = _doOpen();
    _openFuture = future;
    try {
      return await future;
    } catch (_) {
      _openFuture = null;
      rethrow;
    }
  }

  Future<Database> _doOpen() async {
    await initFfi();
    if (_cachedDbPath == null) {
      final dir = await AppDataRoot.applicationSupportDirectory();
      final sub = Directory(p.join(dir.path, 'querya_desktop'));
      if (!await sub.exists()) await sub.create(recursive: true);
      _cachedDbPath = p.join(sub.path, _dbName);
    }
    final db = await databaseFactoryFfi.openDatabase(
      _cachedDbPath!,
      options: OpenDatabaseOptions(
        version: LocalDbSchema.version,
        onCreate: LocalDbSchema.onCreate,
        onUpgrade: LocalDbSchema.onUpgrade,
        // A newer schema: refuse, so sqflite does not stamp the old version
        // on it (the open transaction rolls back).
        onDowngrade: (db, found, supported) => throw LocalDbNewerSchemaException(
          found: found,
          supported: supported,
          path: _cachedDbPath!,
        ),
        onOpen: LocalDbSchema.onOpen,
      ),
    );
    _db = db;
    _openFuture = null;
    // Safety net for the common case (db already at the current version, so
    // neither onCreate nor onUpgrade ran this open): _onCreate/_onUpgrade
    // already set this when they do run, ahead of any secret read/write.
    ConnectionSecretsStore.profileId ??= await LocalDbSchema.ensureProfileId(db);
    return db;
  }

  /// Queries an active PRAGMA setting from the database for verification and diagnostic purposes.
  Future<String> getPragma(String pragmaName) async {
    final db = await _open();
    final res = await db.rawQuery('PRAGMA $pragmaName');
    if (res.isNotEmpty && res.first.values.isNotEmpty) {
      return res.first.values.first.toString();
    }
    return '';
  }

  Future<String?> readErdLayout(int connectionId, String scope) async {
    final db = await _open();
    final rows = await db.query(
      'erd_layouts',
      columns: ['payload'],
      where: 'connection_id = ? AND scope = ?',
      whereArgs: [connectionId, scope],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['payload'] as String?;
  }

  Future<void> writeErdLayout(
    int connectionId,
    String scope,
    String payload,
  ) async {
    final db = await _open();
    await db.rawInsert(
      'INSERT OR REPLACE INTO erd_layouts '
      '(connection_id, scope, payload, updated_at) VALUES (?, ?, ?, ?)',
      [connectionId, scope, payload, DateTime.now().toUtc().toIso8601String()],
    );
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
    final count = sqliteInt(countRows.first['c']) ?? 0;
    final excess = count - maxEntries;
    if (excess <= 0) return;

    final overflow = await db.rawQuery(
      '''
      SELECT id FROM sql_query_history
      WHERE connection_id = ? AND database_name IS NOT DISTINCT FROM ?
      ORDER BY id ASC
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
      ORDER BY id DESC
      LIMIT ?
      ''',
      [connectionId, dbKey, limit],
    );
    return rows.map(SqlQueryHistoryEntry.fromMap).toList();
  }

  /// Removes all history rows for [connectionId] (every database bucket).
  Future<void> clearSqlQueryHistoryForConnection(int connectionId) async {
    _historyInsertCounts.removeWhere((k, _) => k.startsWith('$connectionId::'));
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
    final dbKey = _normalizeHistoryDatabaseName(databaseName);
    _historyInsertCounts.remove('$connectionId::${dbKey ?? ''}');
    final db = await _open();
    await db.rawDelete(
      '''
      DELETE FROM sql_query_history
      WHERE connection_id = ? AND database_name IS NOT DISTINCT FROM ?
      ''',
      [connectionId, dbKey],
    );
  }

  /// Appends one executed mutation to the audit trail and trims the table to
  /// [kMutationAuditCap] rows. Never throws: auditing must not break a query.
  Future<void> recordMutationAudit({
    int? connectionId,
    required String connectionName,
    String? environment,
    String? databaseName,
    required String sqlText,
    int? rowsAffected,
    required MutationAuditSource source,
  }) async {
    final sql = sqlText.trim();
    if (sql.isEmpty) return;
    try {
      final db = await _open();
      await db.insert('mutation_audit', {
        'connection_id': connectionId,
        'connection_name': connectionName,
        'environment': environment,
        'database_name': _normalizeHistoryDatabaseName(databaseName),
        'sql_text': sql,
        'rows_affected': rowsAffected,
        'source': source.storageValue,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      });
      _mutationAuditInsertCount++;
      if (_mutationAuditInsertCount >= 50) {
        _mutationAuditInsertCount = 0;
        await db.rawDelete(
          'DELETE FROM mutation_audit WHERE id <= ('
          'SELECT id FROM mutation_audit ORDER BY id DESC LIMIT 1 OFFSET ?)',
          [kMutationAuditCap],
        );
      }
    } catch (e) {
      // Best effort, but a missing audit trail should not be invisible.
      debugPrint('LocalDb: could not record a mutation audit entry: $e');
    }
  }

  var _mutationAuditInsertCount = 0;

  /// Newest-first audit entries, optionally for one connection.
  Future<List<MutationAuditEntry>> listMutationAudit({
    int? connectionId,
    int limit = 200,
  }) async {
    final db = await _open();
    final rows = await db.query(
      'mutation_audit',
      where: connectionId == null ? null : 'connection_id = ?',
      whereArgs: connectionId == null ? null : [connectionId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(MutationAuditEntry.fromMap).toList();
  }

  Future<void> clearMutationAudit() async {
    final db = await _open();
    await db.delete('mutation_audit');
    _mutationAuditInsertCount = 0;
  }

  /// Appends one MCP tool call and keeps the newest [kMcpActivityCap].
  /// Never throws: logging must not break a tool call.
  Future<void> recordMcpActivity(McpActivityEntry entry) async {
    try {
      final db = await _open();
      final map = entry.toMap()..remove('id');
      await db.insert('mcp_activity', map);
      await db.rawDelete(
        'DELETE FROM mcp_activity WHERE id <= ('
        'SELECT id FROM mcp_activity ORDER BY id DESC LIMIT 1 OFFSET ?)',
        [kMcpActivityCap],
      );
    } catch (e) {
      debugPrint('LocalDb: could not record MCP activity: $e');
    }
  }

  /// Newest-first MCP tool calls.
  Future<List<McpActivityEntry>> listMcpActivity({int limit = 200}) async {
    final db = await _open();
    final rows =
        await db.query('mcp_activity', orderBy: 'id DESC', limit: limit);
    return rows.map(McpActivityEntry.fromMap).toList();
  }

  Future<void> clearMcpActivity() async {
    final db = await _open();
    await db.delete('mcp_activity');
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

  /// Removes the folder; its connections stay, without a folder.
  ///
  /// `connections.folder_id` is `ON DELETE CASCADE`, which would delete them
  /// with it. They are detached first, so the cascade finds nothing: no schema
  /// migration of the connections table is needed.
  Future<void> removeFolder(String name) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE connections SET folder_id = NULL WHERE folder_id IN '
        '(SELECT id FROM folders WHERE name = ?)',
        [name],
      );
      await txn.delete('folders', where: 'name = ?', whereArgs: [name]);
    });
  }

  /// Moves a connection into the folder [folderId], or out of any folder when
  /// it is null. Only the folder changes: secrets and settings are untouched.
  Future<void> setConnectionFolder(int connectionId, int? folderId) async {
    final db = await _open();
    await db.update(
      'connections',
      {'folder_id': folderId},
      where: 'id = ?',
      whereArgs: [connectionId],
    );
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
    return sqliteInt(rows.first['id']);
  }

  /// Returns all saved connections.
  ///
  /// By default, passwords and connection strings are NOT eagerly hydrated from
  /// the platform secure store to avoid IPC bottlenecks, Keychain lockups, and
  /// D-Bus timeouts during sidebar/startup population. Secrets are resolved
  /// on-demand when a connection is initiated.
  Future<List<ConnectionRow>> getConnections(
      {bool hydrateSecrets = false}) async {
    final db = await _open();
    final rows =
        await db.query('connections', orderBy: 'sort_order ASC, name ASC');
    if (!hydrateSecrets) {
      return rows.map((m) => ConnectionRow.fromMap(m)).toList();
    }
    final futures =
        rows.map((m) => _hydrateConnection(ConnectionRow.fromMap(m)));
    return Future.wait(futures);
  }

  static Future<ConnectionRow> _hydrateConnection(ConnectionRow row) async {
    if (row.id == null) return row;
    try {
      final secrets = await ConnectionSecretsStore.readForConnection(row.id!);
      return row.copyWith(
        password: secrets.password ?? row.password,
        connectionString: secrets.connectionString ?? row.connectionString,
      );
    } catch (e) {
      debugPrint(
          'LocalDb._hydrateConnection failed for connection ${row.id}: $e');
      return row;
    }
  }

  /// Hydrates secrets for a single [ConnectionRow] on demand.
  Future<ConnectionRow> hydrateConnection(ConnectionRow row) =>
      _hydrateConnection(row);

  /// Retrieves a single connection by [id], optionally hydrating secrets.
  Future<ConnectionRow?> getConnectionById(int id,
      {bool hydrateSecrets = false}) async {
    final db = await _open();
    final rows =
        await db.query('connections', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final row = ConnectionRow.fromMap(rows.first);
    if (!hydrateSecrets) return row;
    return _hydrateConnection(row);
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
      if (row.sshSecrets != null) {
        await ConnectionSecretsStore.writeSshSecretsForConnection(
          id,
          password: row.sshSecrets!.password,
          privateKey: row.sshSecrets!.privateKey,
          passphrase: row.sshSecrets!.passphrase,
          jumpPassword: row.sshSecrets!.jumpPassword,
        );
      }
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
    final previousSsh =
        await ConnectionSecretsStore.readSshSecretsForConnection(row.id!);

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
      if (row.sshSecrets != null) {
        await ConnectionSecretsStore.writeSshSecretsForConnection(
          row.id!,
          password: row.sshSecrets!.password,
          privateKey: row.sshSecrets!.privateKey,
          passphrase: row.sshSecrets!.passphrase,
          jumpPassword: row.sshSecrets!.jumpPassword,
        );
      } else if (row.sshTunnelConfig?.enabled != true) {
        // The tunnel was turned off: its password and key do not stay in the
        // keyring (#1311).
        await ConnectionSecretsStore.writeSshSecretsForConnection(row.id!);
      }
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
        // The SSH secrets may be half written too (four keys, one by one).
        await ConnectionSecretsStore.writeSshSecretsForConnection(
          row.id!,
          password: previousSsh.password,
          privateKey: previousSsh.privateKey,
          passphrase: previousSsh.passphrase,
          jumpPassword: previousSsh.jumpPassword,
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
    _historyInsertCounts.removeWhere((k, _) => k.startsWith('$id::'));
    try {
      await ConnectionSecretsStore.deleteForConnection(id);
    } catch (_) {
      // Do not block removing the connection metadata when the OS store fails.
    }
    final db = await _open();
    await db.delete('connections', where: 'id = ?', whereArgs: [id]);
  }

  /// Resolves the absolute path to `querya.db`.
  Future<String> databasePath() async {
    if (_cachedDbPath != null) return _cachedDbPath!;
    final dir = await AppDataRoot.applicationSupportDirectory();
    final sub = Directory(p.join(dir.path, 'querya_desktop'));
    if (!await sub.exists()) await sub.create(recursive: true);
    _cachedDbPath = p.join(sub.path, _dbName);
    return _cachedDbPath!;
  }

  /// Explicitly opens the database or throws if opening/migrating fails.
  Future<Database> open() => _open();

  /// Removes stale WAL, SHM, and lock sidecars (e.g. after a process crash or freeze).
  Future<void> removeWalAndLockFiles() async {
    await close();
    final dbPath = await databasePath();
    final walFile = File('$dbPath-wal');
    final shmFile = File('$dbPath-shm');
    final lockFile = File('$dbPath-lock');
    if (await walFile.exists()) {
      try {
        await walFile.delete();
      } catch (e) {
        logIgnored('local_db', e);
      }
    }
    if (await shmFile.exists()) {
      try {
        await shmFile.delete();
      } catch (e) {
        logIgnored('local_db', e);
      }
    }
    if (await lockFile.exists()) {
      try {
        await lockFile.delete();
      } catch (e) {
        logIgnored('local_db', e);
      }
    }
  }

  /// Copies `querya.db` to `querya.db.pre-<from>-<to>.bak` before an in-app
  /// update and keeps the newest [UpdateBackup.keep] copies (#1497). Closes
  /// the database first; the next query opens it again.
  Future<String> backupBeforeUpdate({
    required String fromVersion,
    required String toVersion,
  }) async {
    await close();
    return UpdateBackup.create(
      dbPath: await databasePath(),
      fromVersion: fromVersion,
      toVersion: toVersion,
    );
  }

  /// Creates a timestamped backup copy of `querya.db` (and any sidecar files)
  /// in the same directory and returns the backup file path.
  Future<String> backupDatabaseFile() async {
    await close();
    final dbPath = await databasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw FileSystemException('Database file does not exist', dbPath);
    }
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = '$dbPath.corrupted.$timestamp.bak';
    await dbFile.copy(backupPath);

    final walFile = File('$dbPath-wal');
    if (await walFile.exists()) {
      try {
        await walFile.copy('$backupPath-wal');
      } catch (e) {
        logIgnored('local_db', e);
      }
    }
    return backupPath;
  }

  /// Resets the database file by creating a backup and removing the corrupted db
  /// so a fresh schema can be created on the next launch.
  Future<void> resetDatabaseFile() async {
    await close();
    final dbPath = await databasePath();
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      try {
        await backupDatabaseFile();
      } catch (e) {
        logIgnored('local_db', e);
      }
      try {
        await dbFile.delete();
      } catch (e) {
        logIgnored('local_db', e);
      }
    }
    await removeWalAndLockFiles();
  }

  Future<void> close() async {
    _openFuture = null;
    await _db?.close();
    _db = null;
    _cachedDbPath = null;
  }
}

/// Maximum rows kept in the mutation audit trail.
const int kMutationAuditCap = 10000;
