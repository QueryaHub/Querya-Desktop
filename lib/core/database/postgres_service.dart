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

/// Lease for a pooled [PostgresConnection]. Call [release] when the UI is done
/// (typically in [State.dispose]).
class PgLease {
  PgLease._(this._service, this._key, this.connection);

  final PostgresService _service;
  final String _key;
  final PostgresConnection connection;

  bool _released = false;

  /// Returns the connection to the pool (ref-count / idle dispose).
  void release() {
    if (_released) return;
    _released = true;
    _service._release(_key);
  }
}

/// Pooled PostgreSQL connections keyed by `(connection id, database, session mode)`.
///
/// Matches the idea of [MongoService]: reuse TCP sessions instead of opening one
/// per widget. Idle connections are closed after [idleDisposeDelay].
///
/// Use [interrupt] to force-close a pooled connection (e.g. user navigates away
/// while a query is still running); the next [acquire] opens a new connection.
class PostgresService {
  PostgresService._();
  static final PostgresService instance = PostgresService._();

  static const Duration idleDisposeDelay = Duration(seconds: 8);

  final Map<String, _PoolEntry> _pool = {};

  String _key(int? id, String database, PgSessionMode mode) =>
      '${id ?? 0}::$database::${mode.name}';

  /// Obtains a connected [PostgresConnection], incrementing the pool ref-count.
  Future<PgLease> acquire(
    ConnectionRow row, {
    required String database,
    PgSessionMode mode = PgSessionMode.readOnly,
  }) async {
    final key = _key(row.id, database, mode);
    var entry = _pool[key];
    if (entry != null) {
      entry.idleTimer?.cancel();
      entry.idleTimer = null;
      entry.refs++;
      if (!entry.connection.isConnected) {
        await entry.connection.connect();
        await entry.connection.setSessionReadOnly(mode == PgSessionMode.readOnly);
      }
      return PgLease._(this, key, entry.connection);
    }

    final conn = PostgresConnection.fromConnectionRow(row, database: database);
    await conn.connect();
    await conn.setSessionReadOnly(mode == PgSessionMode.readOnly);
    entry = _PoolEntry(conn)..refs = 1;
    _pool[key] = entry;
    return PgLease._(this, key, conn);
  }

  void _release(String key) {
    final entry = _pool[key];
    if (entry == null) return;
    entry.refs--;
    if (entry.refs > 0) return;
    entry.idleTimer?.cancel();
    entry.idleTimer = Timer(idleDisposeDelay, () {
      final e = _pool[key];
      if (e == null || e.refs > 0) return;
      e.idleTimer = null;
      unawaited(e.connection.disconnect());
      _pool.remove(key);
    });
  }

  /// Force-closes the pooled connection for this key (drops client-side I/O;
  /// server may still finish the query until it notices disconnect).
  ///
  /// Safe to call when leaving a screen while `_loading` / long query.
  void interrupt(
    ConnectionRow row, {
    required String database,
    PgSessionMode mode = PgSessionMode.readOnly,
  }) {
    final key = _key(row.id, database, mode);
    final entry = _pool.remove(key);
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
