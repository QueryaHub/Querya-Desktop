import 'dart:math';

import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `app_settings` key under which each profile database's random id is
/// stored (see [LocalDbSchema.ensureProfileId] and issue #986).
const profileIdSettingKey = 'profile_id';

String _generateProfileId() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

int? _sqliteInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// The schema of the local database: its creation, the upgrade from every
/// older version, and the pragmas set on each open.
///
/// [version] is bumped with each schema change; add the step to [onUpgrade]
/// under `oldVersion < N` and the table to [onCreate].
abstract final class LocalDbSchema {
  static const version = 13;

  /// Run on every open, after create or upgrade.
  static Future<void> onOpen(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA journal_mode = WAL');
    await db.execute('PRAGMA busy_timeout = 5000');
    await db.execute('PRAGMA synchronous = NORMAL');
  }

  static Future<void> onCreate(Database db, int version) async {
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
    await createMutationAuditTable(db);
    await createMcpActivityTable(db);
    await createErdLayoutsTable(db);
    ConnectionSecretsStore.profileId = await ensureProfileId(db);
  }

  /// Local audit trail of executed data / schema changes (#1062). Not linked
  /// to `connections` so entries outlive a deleted connection; the connection
  /// name is stored as a snapshot.
  static Future<void> createMutationAuditTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mutation_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        connection_id INTEGER,
        connection_name TEXT NOT NULL,
        environment TEXT,
        database_name TEXT,
        sql_text TEXT NOT NULL,
        rows_affected INTEGER,
        source TEXT NOT NULL,
        recorded_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_mutation_audit_recorded
      ON mutation_audit (id DESC)
    ''');
  }

  /// Calls made by MCP clients (#1136), newest kept, capped at
  /// [kMcpActivityCap]. Connection name is a snapshot, like the audit.
  static Future<void> createMcpActivityTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mcp_activity (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recorded_at TEXT NOT NULL,
        client TEXT NOT NULL,
        tool TEXT NOT NULL,
        connection_id INTEGER,
        connection_name TEXT,
        sql_text TEXT,
        row_count INTEGER,
        duration_ms INTEGER NOT NULL,
        error TEXT,
        refusal_rule TEXT
      )
    ''');
  }

  static Future<void> onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    // Every upgrade path needs app_settings before it can read/write the
    // profile id; the oldVersion < 4 block below also creates this table for
    // installs that predate it, but IF NOT EXISTS keeps this idempotent.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
    ''');
    ConnectionSecretsStore.profileId = await ensureProfileId(db);

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
    // (oldVersion < 4 used to CREATE TABLE app_settings here; the
    // CREATE TABLE IF NOT EXISTS above now covers that install path too.)
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
    if (oldVersion < 9) {
      // Adopt this profile's own pre-#986 unnamespaced keyring secrets (if
      // any) under the namespaced key generated above, so this database's
      // connections keep working after another profile with an overlapping
      // connection id also upgrades.
      final rows = await db.query('connections', columns: ['id']);
      for (final m in rows) {
        final id = _sqliteInt(m['id']);
        if (id == null) continue;
        await ConnectionSecretsStore.adoptLegacyKeysForConnection(id);
      }
    }
    if (oldVersion < 10) {
      await createMutationAuditTable(db);
    }
    if (oldVersion < 11) {
      await createMcpActivityTable(db);
    }
    if (oldVersion >= 11 && oldVersion < 12) {
      // The rule that refused a call, next to its error text.
      await db.execute('ALTER TABLE mcp_activity ADD COLUMN refusal_rule TEXT');
    }
    if (oldVersion < 13) {
      await createErdLayoutsTable(db);
    }
  }

  /// What the user arranged on an ER diagram (#1275), one row per connection
  /// and scope (database / schema), removed with its connection.
  static Future<void> createErdLayoutsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS erd_layouts (
        connection_id INTEGER NOT NULL
          REFERENCES connections(id) ON DELETE CASCADE,
        scope TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (connection_id, scope)
      )
    ''');
  }


  /// Returns this profile database's random id (see issue #986), generating
  /// and persisting one on first use. Namespaces [ConnectionSecretsStore]
  /// keys so two profile databases never collide in the shared OS keyring.
  static Future<String> ensureProfileId(Database db) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [profileIdSettingKey],
      limit: 1,
    );
    final existing = rows.isNotEmpty ? rows.first['value'] as String? : null;
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _generateProfileId();
    await db.rawInsert(
      'INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)',
      [profileIdSettingKey, id],
    );
    return id;
  }
}
