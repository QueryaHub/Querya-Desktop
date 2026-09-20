import 'dart:async';

import 'package:querya_desktop/core/database/connection_pool_lock.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Session policy for pooled connections: browse vs SQL editor (writes).
enum MysqlSessionMode {
  /// Tree catalog, stats, and Table Browser SELECT/COUNT.
  readOnly,

  /// SQL editor. Must not be shared with Table Browser.
  readWrite,

  /// Table Browser Save (own TCP session so START TRANSACTION / SET / USE do not leak).
  tableWrite,
}

extension MysqlSessionModeReadOnly on MysqlSessionMode {
  bool get isReadOnlySession => this == MysqlSessionMode.readOnly;
}

typedef MysqlPoolConnectionFactory = Future<MysqlConnection> Function(
  ConnectionRow row, {
  required String database,
  required MysqlSessionMode mode,
});

/// Lease for a pooled [MysqlConnection]. Call [release] when the UI is done.
class MysqlLease {
  MysqlLease._(this._pool, this._key, this.connection);

  final MysqlConnectionPool _pool;
  final String _key;
  final MysqlConnection connection;

  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _pool._release(_key);
  }
}

/// Pooled MySQL connections keyed by `(connection id, database, session mode)`.
class MysqlConnectionPool {
  MysqlConnectionPool({
    required this.createAndConnect,
    this.idleDisposeDelay = defaultIdleDisposeDelay,
    this.maxEntries = defaultMaxEntries,
  });

  static const Duration defaultIdleDisposeDelay = Duration(seconds: 4);
  static const int defaultMaxEntries = 32;

  final MysqlPoolConnectionFactory createAndConnect;
  final Duration idleDisposeDelay;
  final int maxEntries;

  final Map<String, _PoolEntry> _pool = {};
  final PoolEntryLock<MysqlConnection> _creationLock = PoolEntryLock();

  String keyFor(int? id, String database, MysqlSessionMode mode) =>
      '${id ?? 0}::$database::${mode.name}';

  Future<MysqlLease> acquire(
    ConnectionRow row, {
    required String database,
    MysqlSessionMode mode = MysqlSessionMode.readOnly,
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
      return MysqlLease._(this, k, entry.connection);
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
    } on MysqlConnectionException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        MysqlConnectionException(
          'Failed to acquire MySQL connection for database "$database": $e',
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
    return MysqlLease._(this, k, entry.connection);
  }

  void _evictIfNeededBeforeNewSlot() {
    while (_pool.length >= maxEntries) {
      final idle = _pool.entries.where((e) => e.value.refs == 0).toList();
      if (idle.isEmpty) {
        throw StateError(
          'MySQL connection pool exhausted: $maxEntries slots in use.',
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

  void interrupt(
    ConnectionRow row, {
    required String database,
    MysqlSessionMode mode = MysqlSessionMode.readOnly,
  }) {
    final k = keyFor(row.id, database, mode);
    _removeEntryClosing(k);
  }

  /// Force-closes every session mode for this connection+database.
  void interruptAllModes(
    ConnectionRow row, {
    required String database,
  }) {
    for (final mode in MysqlSessionMode.values) {
      interrupt(row, database: database, mode: mode);
    }
  }

  /// Whether the SQL-editor slot currently has an open transaction.
  Future<bool> hasOpenSqlTransaction(
    ConnectionRow row, {
    required String database,
  }) async {
    final entry = _pool[keyFor(row.id, database, MysqlSessionMode.readWrite)];
    if (entry == null || !entry.connection.isConnected) return false;
    return await entry.connection.inOpenTransaction() ?? false;
  }

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

  final MysqlConnection connection;
  int refs = 0;
  Timer? idleTimer;
  DateTime lastUsed;

  void touch() => lastUsed = DateTime.now();
}
