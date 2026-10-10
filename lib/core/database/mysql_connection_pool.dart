import 'dart:async';

import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:querya_desktop/core/database/querya_database_exception.dart';
import 'package:querya_desktop/core/database/connection_pool_lock.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Session policy for pooled connections: browse vs SQL editor (writes).
/// Longest statement an MCP session may run; the server stops it after this.
const Duration mcpStatementTimeout = Duration(seconds: 15);

enum MysqlSessionMode {
  /// Tree catalog, stats, and Table Browser SELECT/COUNT.
  readOnly,

  /// SQL editor. Must not be shared with Table Browser.
  readWrite,

  /// Table Browser Save (own TCP session so START TRANSACTION / SET / USE do not leak).
  tableWrite,
  /// MCP clients: a read-only session of their own, so an agent never shares
  /// the user's session. Statements are bounded by [statementTimeout].
  mcp,
}

extension MysqlSessionModeReadOnly on MysqlSessionMode {
  bool get isReadOnlySession => this == MysqlSessionMode.readOnly || this == MysqlSessionMode.mcp;

  /// Server-side limit for every statement on this session, or null for none.
  Duration? get statementTimeout =>
      this == MysqlSessionMode.mcp ? mcpStatementTimeout : null;
}

typedef MysqlPoolConnectionFactory = Future<MysqlConnection> Function(
  ConnectionRow row, {
  required String database,
  required MysqlSessionMode mode,
});

/// Lease for a pooled [MysqlConnection]. Call [release] when the UI is done.
class MysqlLease {
  MysqlLease._(this._pool, this._entry, this.connection);

  final MysqlConnectionPool _pool;
  final _PoolEntry _entry;
  final MysqlConnection connection;

  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _pool._release(_entry);
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
      await _ensureConnected(entry, mode);
      return MysqlLease._(this, entry, entry.connection);
    }

    try {
      await _creationLock.createIfAbsent(k, () async {
        _evictIfNeededBeforeNewSlot();
        final conn =
            await createAndConnect(row, database: database, mode: mode);
        _pool[k] = _PoolEntry(conn, k);
        return conn;
      });
    } on StateError {
      rethrow;
    } on PoolExhaustedException {
      rethrow;
    } on MysqlConnectionException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        MysqlConnectionException(
          'Failed to acquire MySQL connection for database "$database": '
          '${describeDatabaseError(e, driver: DatabaseDriver.mysql)}',
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
    await _ensureConnected(entry, mode);
    return MysqlLease._(this, entry, entry.connection);
  }

  void _evictIfNeededBeforeNewSlot() {
    while (_pool.length >= maxEntries) {
      final idle = _pool.entries.where((e) => e.value.refs == 0).toList();
      if (idle.isEmpty) {
        throw PoolExhaustedException(
          'The MySQL connection pool is full: $maxEntries sessions are in use',
          remediationHint: 'Close tabs or connections you no longer use, '
              'then try again',
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

  /// Releases one lease on [entry]. A lease taken before an [interrupt] points
  /// at an entry that is no longer in the pool: it must not touch the entry
  /// that replaced it under the same key, so it does nothing.
  /// Makes the entry's connection usable for a lease that was just counted.
  /// When the reconnect fails the count is given back, so the entry can be
  /// idle-disposed or evicted instead of staying "in use" for good (#1306).
  Future<void> _ensureConnected(_PoolEntry entry, MysqlSessionMode mode) async {
    if (entry.connection.isConnected) return;
    try {
      await _reconnect(entry, mode);
    } catch (_) {
      _release(entry);
      rethrow;
    }
  }

  /// Brings a dropped entry back with one reconnect and one session setting,
  /// even when several callers ask at once; they all wait for the same attempt.
  Future<void> _reconnect(_PoolEntry entry, MysqlSessionMode mode) {
    final inFlight = entry.reconnecting;
    if (inFlight != null) return inFlight;
    final attempt = () async {
      await entry.connection.connect();
      await entry.connection.configureSession(
        readOnly: mode.isReadOnlySession,
        statementTimeout: mode.statementTimeout,
      );
    }();
    entry.reconnecting = attempt;
    return attempt.whenComplete(() {
      if (identical(entry.reconnecting, attempt)) entry.reconnecting = null;
    });
  }

  void _release(_PoolEntry entry) {
    if (!identical(_pool[entry.key], entry)) return;
    entry.refs--;
    assert(
      entry.refs >= 0,
      'pool entry ${entry.key} released more often than leased',
    );
    if (entry.refs > 0) return;
    entry.idleTimer?.cancel();
    entry.idleTimer = Timer(idleDisposeDelay, () {
      if (!identical(_pool[entry.key], entry) || entry.refs > 0) return;
      entry.idleTimer = null;
      unawaited(entry.connection.disconnect());
      _pool.remove(entry.key);
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
  _PoolEntry(this.connection, this.key) : lastUsed = DateTime.now();

  final MysqlConnection connection;
  final String key;
  Future<void>? reconnecting;
  int refs = 0;
  Timer? idleTimer;
  DateTime lastUsed;

  void touch() => lastUsed = DateTime.now();
}
