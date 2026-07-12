import 'dart:async';

import 'package:querya_desktop/core/database/connection_pool_lock.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Session policy for pooled SQLite connections.
enum SqliteSessionMode {
  readOnly,
  readWrite,
}

/// Factory to build a connected SQLite connection.
typedef SqlitePoolConnectionFactory = Future<SqliteConnection> Function(
  ConnectionRow row, {
  required SqliteSessionMode mode,
});

/// Lease for a pooled [SqliteConnection]. Call [release] when the UI is done.
class SqliteLease {
  SqliteLease._(this._pool, this._key, this.connection);

  final SqliteConnectionPool _pool;
  final String _key;
  final SqliteConnection connection;

  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _pool._release(_key);
  }
}

class _PoolEntry {
  _PoolEntry(this.connection);
  final SqliteConnection connection;
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

  static const Duration defaultIdleDisposeDelay = Duration(seconds: 8);
  static const int defaultMaxEntries = 32;

  final SqlitePoolConnectionFactory createAndConnect;
  final Duration idleDisposeDelay;
  final int maxEntries;

  final Map<String, _PoolEntry> _pool = {};
  final PoolEntryLock<SqliteConnection> _creationLock = PoolEntryLock();

  String keyFor(int? id, SqliteSessionMode mode) =>
      '${id ?? 0}::${mode.name}';

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
      if (!entry.connection.isConnected) {
        await entry.connection.connect();
      }
      return SqliteLease._(this, k, entry.connection);
    }

    try {
      await _creationLock.createIfAbsent(k, () async {
        _evictIfNeededBeforeNewSlot();
        final conn = await createAndConnect(row, mode: mode);
        _pool[k] = _PoolEntry(conn);
        return conn;
      });
    } on StateError {
      rethrow;
    } on SqliteConnectionException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        SqliteConnectionException(
          'Failed to acquire SQLite connection: $e',
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
    if (!entry.connection.isConnected) {
      await entry.connection.connect();
    }
    return SqliteLease._(this, k, entry.connection);
  }

  void _evictIfNeededBeforeNewSlot() {
    while (_pool.length >= maxEntries) {
      final idle = _pool.entries.where((e) => e.value.refs == 0).toList();
      if (idle.isEmpty) {
        throw StateError(
          'SQLite connection pool exhausted: $maxEntries slots in use.',
        );
      }
      idle.sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
      _removeEntryClosing(idle.first.key);
    }
  }

  void _removeEntryClosing(String k) {
    final entry = _pool.remove(k);
    if (entry == null) return;
    entry.idleTimer?.cancel();
    unawaited(entry.connection.forceClose());
  }

  void _release(String key) {
    final entry = _pool[key];
    if (entry == null) return;
    entry.refs--;
    if (entry.refs <= 0) {
      entry.refs = 0;
      entry.idleTimer?.cancel();
      entry.idleTimer = Timer(idleDisposeDelay, () {
        final e = _pool[key];
        if (e == null || e.refs > 0) return;
        e.idleTimer = null;
        unawaited(e.connection.disconnect());
        _pool.remove(key);
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

  Future<void> disconnectAll() async {
    final entries = _pool.values.toList();
    _pool.clear();
    for (final entry in entries) {
      entry.idleTimer?.cancel();
      await entry.connection.forceClose();
    }
  }
}
