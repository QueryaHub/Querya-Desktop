import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbName = 'querya.db';
const _dbVersion = 5;

int? _sqliteInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
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
      final dir = await getApplicationSupportDirectory();
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
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE connections ADD COLUMN password TEXT');
      await db.execute('ALTER TABLE connections ADD COLUMN database_name TEXT');
      await db.execute('ALTER TABLE connections ADD COLUMN auth_source TEXT');
      await db.execute('ALTER TABLE connections ADD COLUMN use_ssl INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE connections ADD COLUMN connection_string TEXT');
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
    final rows = await db.query('folders', columns: ['id'], where: 'name = ?', whereArgs: [name]);
    if (rows.isEmpty) return null;
    return _sqliteInt(rows.first['id']);
  }

  Future<List<ConnectionRow>> getConnections() async {
    final db = await _open();
    final rows = await db.query('connections', orderBy: 'sort_order ASC, name ASC');
    final out = <ConnectionRow>[];
    for (final m in rows) {
      out.add(await _hydrateConnection(ConnectionRow.fromMap(m)));
    }
    return out;
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
  Future<int> addConnection(ConnectionRow row) async {
    final db = await _open();
    final id = await db.insert('connections', row.toPersistenceMap());
    await ConnectionSecretsStore.writeForConnection(
      id,
      password: row.password,
      connectionString: row.connectionString,
    );
    return id;
  }

  Future<void> removeConnection(int id) async {
    await ConnectionSecretsStore.deleteForConnection(id);
    final db = await _open();
    await db.delete('connections', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
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
  final int? folderId;
  final int sortOrder;
  final String createdAt;

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
        folderId: _sqliteInt(m['folder_id']),
        sortOrder: _sqliteInt(m['sort_order']) ?? 0,
        createdAt: m['created_at'] as String,
      );
}
