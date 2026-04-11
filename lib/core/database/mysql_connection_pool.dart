import 'dart:async';

import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Session policy for pooled connections: browse vs SQL editor (writes).
enum MysqlSessionMode {
  readOnly,
  readWrite,
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

  static const Duration defaultIdleDisposeDelay = Duration(seconds: 8);
  static const int defaultMaxEntries = 32;

  final MysqlPoolConnectionFactory createAndConnect;
  final Duration idleDisposeDelay;
  final int maxEntries;

  final Map<String, _PoolEntry> _pool = {};

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
        await entry.connection.setSessionReadOnly(
          mode == MysqlSessionMode.readOnly,
        );
      }
      return MysqlLease._(this, k, entry.connection);
    }

    _evictIfNeededBeforeNewSlot();

    final conn = await createAndConnect(row, database: database, mode: mode);
    entry = _PoolEntry(conn)..refs = 1;
    _pool[k] = entry;
    return MysqlLease._(this, k, conn);
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
