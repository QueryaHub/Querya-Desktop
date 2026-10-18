import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/folder_repository.dart';
import 'package:querya_desktop/core/storage/sql_query_history_repository.dart';
import 'package:querya_desktop/core/storage/activity_log_repository.dart';
import 'package:querya_desktop/core/storage/app_settings_repository.dart';
import 'package:querya_desktop/core/storage/connection_repository.dart';
import 'package:querya_desktop/core/storage/local_db_models.dart';
import 'package:querya_desktop/core/storage/local_db_schema.dart';

export 'package:querya_desktop/core/storage/local_db_models.dart';
import 'package:querya_desktop/core/storage/update_backup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/util/log_ignored.dart';

const _dbName = 'querya.db';

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
        onDowngrade: (db, found, supported) =>
            throw LocalDbNewerSchemaException(
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
    ConnectionSecretsStore.profileId ??=
        await LocalDbSchema.ensureProfileId(db);
    return db;
  }

  // One repository per area; the methods below delegate to them.
  late final FolderRepository folders = FolderRepository(_open);
  late final SqlQueryHistoryRepository sqlHistory =
      SqlQueryHistoryRepository(_open);
  late final ActivityLogRepository activity = ActivityLogRepository(_open);
  late final AppSettingsRepository settings = AppSettingsRepository(_open);
  late final ConnectionRepository connections = ConnectionRepository(
    _open,
    onRemoved: sqlHistory.forgetConnection,
  );

  Future<List<String>> getFolders() => folders.getFolders();

  Future<void> addFolder(String name) => folders.addFolder(name);

  Future<void> removeFolder(String name) => folders.removeFolder(name);

  Future<void> setConnectionFolder(int connectionId, int? folderId) =>
      folders.setConnectionFolder(connectionId, folderId);

  Future<void> clearFolders() => folders.clearFolders();

  Future<int?> getFolderIdByName(String name) =>
      folders.getFolderIdByName(name);

  Future<void> recordSqlQueryHistory({
    required int connectionId,
    String? databaseName,
    required String sqlText,
    int maxEntries = kDefaultSqlHistoryCap,
    bool forcePrune = false,
  }) =>
      sqlHistory.recordSqlQueryHistory(
          connectionId: connectionId,
          databaseName: databaseName,
          sqlText: sqlText,
          maxEntries: maxEntries,
          forcePrune: forcePrune);

  Future<List<SqlQueryHistoryEntry>> listSqlQueryHistory({
    required int connectionId,
    String? databaseName,
    int limit = 50,
  }) =>
      sqlHistory.listSqlQueryHistory(
          connectionId: connectionId, databaseName: databaseName, limit: limit);

  Future<void> clearSqlQueryHistoryForConnection(int connectionId) =>
      sqlHistory.clearSqlQueryHistoryForConnection(connectionId);

  Future<void> clearSqlQueryHistoryBucket({
    required int connectionId,
    String? databaseName,
  }) =>
      sqlHistory.clearSqlQueryHistoryBucket(
          connectionId: connectionId, databaseName: databaseName);

  Future<void> recordMutationAudit({
    int? connectionId,
    required String connectionName,
    String? environment,
    String? databaseName,
    required String sqlText,
    int? rowsAffected,
    required MutationAuditSource source,
  }) =>
      activity.recordMutationAudit(
          connectionId: connectionId,
          connectionName: connectionName,
          environment: environment,
          databaseName: databaseName,
          sqlText: sqlText,
          rowsAffected: rowsAffected,
          source: source);

  Future<List<MutationAuditEntry>> listMutationAudit({
    int? connectionId,
    int limit = 200,
  }) =>
      activity.listMutationAudit(connectionId: connectionId, limit: limit);

  Future<void> clearMutationAudit() => activity.clearMutationAudit();

  Future<void> recordMcpActivity(McpActivityEntry entry) =>
      activity.recordMcpActivity(entry);

  Future<List<McpActivityEntry>> listMcpActivity({int limit = 200}) =>
      activity.listMcpActivity(limit: limit);

  Future<void> clearMcpActivity() => activity.clearMcpActivity();

  Future<String?> getAppSetting(String key) => settings.getAppSetting(key);

  Future<void> setAppSetting(String key, String value) =>
      settings.setAppSetting(key, value);

  Future<void> deleteAppSetting(String key) => settings.deleteAppSetting(key);

  Future<String?> readErdLayout(int connectionId, String scope) =>
      settings.readErdLayout(connectionId, scope);

  Future<void> writeErdLayout(
    int connectionId,
    String scope,
    String payload,
  ) =>
      settings.writeErdLayout(connectionId, scope, payload);

  Future<List<ConnectionRow>> getConnections({bool hydrateSecrets = false}) =>
      connections.getConnections(hydrateSecrets: hydrateSecrets);

  Future<ConnectionRow> hydrateConnection(ConnectionRow row) =>
      connections.hydrateConnection(row);

  Future<ConnectionRow?> getConnectionById(int id,
          {bool hydrateSecrets = false}) =>
      connections.getConnectionById(id, hydrateSecrets: hydrateSecrets);

  Future<int> addConnection(ConnectionRow row) =>
      connections.addConnection(row);

  Future<void> updateConnection(ConnectionRow row) =>
      connections.updateConnection(row);

  Future<void> removeConnection(int id) => connections.removeConnection(id);

  /// Queries an active PRAGMA setting from the database for verification and diagnostic purposes.
  Future<String> getPragma(String pragmaName) async {
    final db = await _open();
    final res = await db.rawQuery('PRAGMA $pragmaName');
    if (res.isNotEmpty && res.first.values.isNotEmpty) {
      return res.first.values.first.toString();
    }
    return '';
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
