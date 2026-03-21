import 'dart:async';

import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Session policy for pooled connections: browse-only vs ad-hoc SQL (writes).
enum PgSessionMode {
  /// `SET default_transaction_read_only = ON` after connect.
  readOnly,

  /// Read-write session (SQL editor, probes that need catalog writes — rare).
  readWrite,
}

/// Creates a connected [PostgresConnection] for the pool (real or fake in tests).
typedef PostgresPoolConnectionFactory = Future<PostgresConnection> Function(
  ConnectionRow row, {
  required String database,
  required PgSessionMode mode,
});

/// Lease for a pooled [PostgresConnection]. Call [release] when the UI is done
/// (typically in [State.dispose]).
class PgLease {
  PgLease._(this._pool, this._key, this.connection);

  final PostgresConnectionPool _pool;
  final String _key;
  final PostgresConnection connection;

  bool _released = false;

  /// Returns the connection to the pool (ref-count / idle dispose).
  void release() {
    if (_released) return;
    _released = true;
    _pool._release(_key);
  }
}

/// Pooled PostgreSQL connections keyed by `(connection id, database, session mode)`.
///
/// Use [interrupt] to force-close a pooled connection (e.g. user navigates away
/// while a query is still running); the next [acquire] opens a new connection.
class PostgresConnectionPool {
  PostgresConnectionPool({
    required this.createAndConnect,
    this.idleDisposeDelay = defaultIdleDisposeDelay,
    this.maxEntries = defaultMaxEntries,
  });

  static const Duration defaultIdleDisposeDelay = Duration(seconds: 8);

  /// Max distinct pool keys `(connection id, database, mode)`. When full,
  /// least-recently-used **idle** slots (`refs == 0`) are closed first.
  static const int defaultMaxEntries = 32;

  final PostgresPoolConnectionFactory createAndConnect;
  final Duration idleDisposeDelay;
  final int maxEntries;

  final Map<String, _PoolEntry> _pool = {};

  String keyFor(int? id, String database, PgSessionMode mode) =>
      '${id ?? 0}::$database::${mode.name}';

  /// Obtains a connected [PostgresConnection], incrementing the pool ref-count.
  Future<PgLease> acquire(
    ConnectionRow row, {
    required String database,
    PgSessionMode mode = PgSessionMode.readOnly,
  }) async {
    final k = keyFor(row.id, database, mode);
    var entry = _pool[k];
    if (entry != null) {
      entry.touch();
      entry.idleTimer?.cancel();
      entry.idleTimer = null;
      entry.refs++;
      if (!entry.connection.isConnected) {
        await entry.connection.connect();
        await entry.connection.setSessionReadOnly(mode == PgSessionMode.readOnly);
      }
      return PgLease._(this, k, entry.connection);
    }

    _evictIfNeededBeforeNewSlot();

    final conn = await createAndConnect(row, database: database, mode: mode);
    entry = _PoolEntry(conn)..refs = 1;
    _pool[k] = entry;
    return PgLease._(this, k, conn);
  }

  /// Drops idle LRU slots until there is room for one more key.
  void _evictIfNeededBeforeNewSlot() {
    while (_pool.length >= maxEntries) {
      final idle = _pool.entries.where((e) => e.value.refs == 0).toList();
      if (idle.isEmpty) {
        throw StateError(
          'PostgreSQL connection pool exhausted: $maxEntries slots in use.',
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

  void _release(String k) {
    final entry = _pool[k];
    if (entry == null) return;
    entry.refs--;
    if (entry.refs > 0) return;
    entry.idleTimer?.cancel();
    entry.idleTimer = Timer(idleDisposeDelay, () {
      final e = _pool[k];
      if (e == null || e.refs > 0) return;
      e.idleTimer = null;
      unawaited(e.connection.disconnect());
      _pool.remove(k);
    });
  }

  /// Force-closes the pooled connection for this key (drops client-side I/O;
  /// server may still finish the query until it notices disconnect).
  void interrupt(
    ConnectionRow row, {
    required String database,
    PgSessionMode mode = PgSessionMode.readOnly,
  }) {
    final k = keyFor(row.id, database, mode);
    _removeEntryClosing(k);
  }

  /// Closes all pooled connections (e.g. app shutdown).
  Future<void> disconnectAll() async {
    for (final entry in _pool.values) {
      entry.idleTimer?.cancel();
      await entry.connection.forceClose();
    }
    _pool.clear();
  }
}

class _PoolEntry {
  _PoolEntry(this.connection) : lastUsed = DateTime.now();

  final PostgresConnection connection;
  int refs = 0;
  Timer? idleTimer;
  DateTime lastUsed;

  void touch() => lastUsed = DateTime.now();
}
