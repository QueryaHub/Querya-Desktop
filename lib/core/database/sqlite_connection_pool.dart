import 'dart:async';
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

    _evictIfNeededBeforeNewSlot();

    final conn = await createAndConnect(row, mode: mode);
    entry = _PoolEntry(conn)..refs = 1;
    _pool[k] = entry;
    return SqliteLease._(this, k, conn);
  }

  void _evictIfNeededBeforeNewSlot() {
    while (_pool.length >= maxEntries) {
      final idle = _pool.entries.where((e) => e.value.refs == 0).toList();
      if (idle.isEmpty) {
        break;
      }
      idle.sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
      final oldestKey = idle.first.key;
      final oldestEntry = _pool.remove(oldestKey);
      oldestEntry?.connection.disconnect();
    }
  }

  void _release(String key) {
    final entry = _pool[key];
    if (entry == null) return;
    entry.refs--;
    if (entry.refs <= 0) {
      entry.refs = 0;
      entry.idleTimer?.cancel();
      entry.idleTimer = Timer(idleDisposeDelay, () {
        if (_pool[key] == entry && entry.refs == 0) {
          _pool.remove(key);
          entry.connection.disconnect();
        }
      });
    }
  }

  void interrupt(
    ConnectionRow row, {
    SqliteSessionMode mode = SqliteSessionMode.readOnly,
  }) {
    final k = keyFor(row.id, mode);
    final entry = _pool.remove(k);
    if (entry != null) {
      entry.idleTimer?.cancel();
      entry.connection.forceClose();
    }
  }

  Future<void> disconnectAll() async {
    final entries = _pool.values.toList();
    _pool.clear();
    for (final entry in entries) {
      entry.idleTimer?.cancel();
      await entry.connection.disconnect();
    }
  }
}
