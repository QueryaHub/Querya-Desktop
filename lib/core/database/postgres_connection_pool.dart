import 'dart:async';

import 'package:querya_desktop/core/database/connection_pool_lock.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Session policy for pooled connections: browse-only vs ad-hoc SQL (writes).
enum PgSessionMode {
  /// `SET default_transaction_read_only = ON` after connect.
  /// Tree catalog, stats, and Table Browser SELECT.
  readOnly,

  /// SQL editor read-write session. Must not be shared with Table Browser.
  readWrite,

  /// Table Browser Save / `REFRESH MATERIALIZED VIEW` (own TCP session).
  tableWrite,
}

extension PgSessionModeReadOnly on PgSessionMode {
  /// Whether this slot should `SET default_transaction_read_only = ON`.
  bool get isReadOnlySession => this == PgSessionMode.readOnly;
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

  static const Duration defaultIdleDisposeDelay = Duration(seconds: 4);

  /// Max distinct pool keys `(connection id, database, mode)`. When full,
  /// least-recently-used **idle** slots (`refs == 0`) are closed first.
  static const int defaultMaxEntries = 32;

  final PostgresPoolConnectionFactory createAndConnect;
  final Duration idleDisposeDelay;
  final int maxEntries;

  final Map<String, _PoolEntry> _pool = {};
  final PoolEntryLock<PostgresConnection> _creationLock = PoolEntryLock();

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
        await entry.connection.setSessionReadOnly(mode.isReadOnlySession);
      }
      return PgLease._(this, k, entry.connection);
    }

    try {
      await _creationLock.createIfAbsent(k, () async {
        _evictIfNeededBeforeNewSlot();
        final conn =
            await createAndConnect(row, database: database, mode: mode);
        _pool[k] = _PoolEntry(conn);
        return conn;
      });
    } on StateError {
      rethrow;
    } on PostgresConnectionException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        PostgresConnectionException(
          'Failed to acquire PostgreSQL connection for database "$database": $e',
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
      await entry.connection.setSessionReadOnly(mode.isReadOnlySession);
    }
    return PgLease._(this, k, entry.connection);
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

  /// Force-closes every session mode for this connection+database.
  void interruptAllModes(
    ConnectionRow row, {
    required String database,
  }) {
    for (final mode in PgSessionMode.values) {
      interrupt(row, database: database, mode: mode);
    }
  }

  /// Whether the SQL-editor slot currently has an open transaction.
  ///
  /// Does not acquire a new connection; returns false if the slot is idle or
  /// disconnected.
  Future<bool> hasOpenSqlTransaction(
    ConnectionRow row, {
    required String database,
  }) async {
    final entry = _pool[keyFor(row.id, database, PgSessionMode.readWrite)];
    if (entry == null || !entry.connection.isConnected) return false;
    return await entry.connection.inOpenTransaction() ?? false;
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
