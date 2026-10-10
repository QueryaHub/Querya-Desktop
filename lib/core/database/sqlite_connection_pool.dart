import 'dart:async';

import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:querya_desktop/core/database/querya_database_exception.dart';
import 'package:querya_desktop/core/database/connection_pool_lock.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Session policy for pooled SQLite connections.
enum SqliteSessionMode {
  /// Tree catalog, overview, and Table Browser SELECT/COUNT.
  readOnly,

  /// SQL editor. Must not be shared with Table Browser.
  readWrite,

  /// Table Browser Save (own `Database` so BEGIN/ATTACH do not leak).
  tableWrite,
  /// MCP clients: a read-only session of their own, so an agent never shares
  /// the user's session. Statements are bounded by [statementTimeout].
  mcp,
}

extension SqliteSessionModeReadOnly on SqliteSessionMode {
  bool get isReadOnlySession => this == SqliteSessionMode.readOnly || this == SqliteSessionMode.mcp;
}

/// Factory to build a connected SQLite connection.
typedef SqlitePoolConnectionFactory = Future<SqliteConnection> Function(
  ConnectionRow row, {
  required SqliteSessionMode mode,
});

/// Lease for a pooled [SqliteConnection]. Call [release] when the UI is done.
class SqliteLease {
  SqliteLease._(this._pool, this._entry, this.connection);

  final SqliteConnectionPool _pool;
  final _PoolEntry _entry;
  final SqliteConnection connection;

  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _pool._release(_entry);
  }
}

class _PoolEntry {
  _PoolEntry(this.connection, this.key);
  final SqliteConnection connection;
  final String key;
  int refs = 0;
  DateTime lastUsed = DateTime.now();
  Timer? idleTimer;

  void touch() {
    lastUsed = DateTime.now();
  }
}

/// Pooled SQLite connections keyed by connection id and session mode.
class SqliteConnectionPool {
  SqliteConnectionPool({
    required this.createAndConnect,
    this.idleDisposeDelay = defaultIdleDisposeDelay,
    this.maxEntries = defaultMaxEntries,
  });

  static const Duration defaultIdleDisposeDelay = Duration(seconds: 4);
  static const int defaultMaxEntries = 32;

  final SqlitePoolConnectionFactory createAndConnect;
  final Duration idleDisposeDelay;
  final int maxEntries;

  final Map<String, _PoolEntry> _pool = {};
  final PoolEntryLock<SqliteConnection> _creationLock = PoolEntryLock();

  String keyFor(int? id, SqliteSessionMode mode) => '${id ?? 0}::${mode.name}';

  Future<SqliteLease> acquire(
    ConnectionRow row, {
    SqliteSessionMode mode = SqliteSessionMode.readOnly,
  }) async {
    final k = keyFor(row.id, mode);
    var entry = _pool[k];
    if (entry != null) {
      entry.touch();
      entry.idleTimer?.cancel();
      entry.idleTimer = null;
      entry.refs++;
      await _ensureConnected(entry);
      return SqliteLease._(this, entry, entry.connection);
    }

    try {
      await _creationLock.createIfAbsent(k, () async {
        _evictIfNeededBeforeNewSlot();
        final conn = await createAndConnect(row, mode: mode);
        _pool[k] = _PoolEntry(conn, k);
        return conn;
      });
    } on StateError {
      rethrow;
    } on PoolExhaustedException {
      rethrow;
    } on SqliteConnectionException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        SqliteConnectionException(
          'Failed to acquire SQLite connection: '
          '${describeDatabaseError(e, driver: DatabaseDriver.sqlite)}',
          cause: e,
          stackTrace: st,
        ),
        st,
      );
    }

    entry = _pool[k]!;
    entry.touch();
    entry.idleTimer?.cancel();
    entry.idleTimer = null;
    entry.refs++;
    await _ensureConnected(entry);
    return SqliteLease._(this, entry, entry.connection);
  }

  void _evictIfNeededBeforeNewSlot() {
    while (_pool.length >= maxEntries) {
      final idle = _pool.entries.where((e) => e.value.refs == 0).toList();
      if (idle.isEmpty) {
        throw PoolExhaustedException(
          'The SQLite connection pool is full: $maxEntries sessions are in use',
          remediationHint: 'Close tabs or connections you no longer use, '
              'then try again',
        );
      }
      idle.sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
      _removeEntryClosing(idle.first.key);
    }
  }

  /// Reconnects a dropped entry for a lease that was just counted. When the
  /// reconnect fails the count is given back, so the entry can be
  /// idle-disposed or evicted instead of staying "in use" for good (#1306).
  Future<void> _ensureConnected(_PoolEntry entry) async {
    if (entry.connection.isConnected) return;
    try {
      await entry.connection.connect();
    } catch (_) {
      _release(entry);
      rethrow;
    }
  }

  void _removeEntryClosing(String k) {
    final entry = _pool.remove(k);
    if (entry == null) return;
    entry.idleTimer?.cancel();
    unawaited(entry.connection.forceClose());
  }

  /// Releases one lease on [entry]. A lease taken before an [interrupt] points
  /// at an entry that is no longer in the pool: it must not touch the entry
  /// that replaced it under the same key, so it does nothing.
  void _release(_PoolEntry entry) {
    if (!identical(_pool[entry.key], entry)) return;
    entry.refs--;
    assert(
      entry.refs >= 0,
      'pool entry ${entry.key} released more often than leased',
    );
    if (entry.refs <= 0) {
      entry.refs = 0;
      entry.idleTimer?.cancel();
      entry.idleTimer = Timer(idleDisposeDelay, () {
        if (!identical(_pool[entry.key], entry) || entry.refs > 0) return;
        entry.idleTimer = null;
        unawaited(entry.connection.disconnect());
        _pool.remove(entry.key);
      });
    }
  }

  void interrupt(
    ConnectionRow row, {
    SqliteSessionMode mode = SqliteSessionMode.readOnly,
  }) {
    final k = keyFor(row.id, mode);
    _removeEntryClosing(k);
  }

  /// Force-closes every session mode for this connection id.
  void interruptAllModes(ConnectionRow row) {
    for (final mode in SqliteSessionMode.values) {
      interrupt(row, mode: mode);
    }
  }

  /// Whether the SQL-editor slot currently has an open transaction.
  Future<bool> hasOpenSqlTransaction(ConnectionRow row) async {
    final entry = _pool[keyFor(row.id, SqliteSessionMode.readWrite)];
    if (entry == null || !entry.connection.isConnected) return false;
    return await entry.connection.inOpenTransaction() ?? false;
  }

  Future<void> disconnectAll() async {
    final entries = _pool.values.toList();
    _pool.clear();
    for (final entry in entries) {
      entry.idleTimer?.cancel();
      await entry.connection.forceClose();
    }
  }
}
