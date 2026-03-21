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
  });

  static const Duration defaultIdleDisposeDelay = Duration(seconds: 8);

  final PostgresPoolConnectionFactory createAndConnect;
  final Duration idleDisposeDelay;

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
      entry.idleTimer?.cancel();
      entry.idleTimer = null;
      entry.refs++;
      if (!entry.connection.isConnected) {
        await entry.connection.connect();
        await entry.connection.setSessionReadOnly(mode == PgSessionMode.readOnly);
      }
      return PgLease._(this, k, entry.connection);
    }

    final conn = await createAndConnect(row, database: database, mode: mode);
    entry = _PoolEntry(conn)..refs = 1;
    _pool[k] = entry;
    return PgLease._(this, k, conn);
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
    final entry = _pool.remove(k);
    if (entry == null) return;
    entry.idleTimer?.cancel();
    unawaited(entry.connection.forceClose());
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
  _PoolEntry(this.connection);

  final PostgresConnection connection;
  int refs = 0;
  Timer? idleTimer;
}
