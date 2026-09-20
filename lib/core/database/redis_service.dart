import 'dart:async';

import '../storage/local_db.dart';
import 'redis_connection.dart';

/// Which workspace surface owns a Redis TCP session for a connection id.
///
/// Overview INFO polling and Explorer SCAN/GET/SELECT cannot share a socket:
/// keep-alive Overview stays mounted under Explorer, and Explorer issues
/// `SELECT` while Overview polls `INFO`.
enum RedisSessionRole {
  /// Overview INFO polling (kept alive under Explorer).
  stats,

  /// Keys/editor SCAN/GET/SET plus `SELECT`.
  explorer,
}

/// Service for Redis connections (Dart redis package, no Java).
class RedisService {
  RedisService._();
  static final RedisService instance = RedisService._();

  final Map<String, RedisConnection> _connections = {};

  String _key(int id, RedisSessionRole role) => '$id::${role.name}';

  /// Returns the existing socket for [role], or creates one without touching
  /// the other role.
  RedisConnection acquire(
    ConnectionRow row, {
    required RedisSessionRole role,
  }) {
    if (row.type != 'redis') {
      throw ArgumentError('Connection type must be redis');
    }
    final id = row.id ?? 0;
    final k = _key(id, role);
    final existing = _connections[k];
    if (existing != null) return existing;
    final conn = RedisConnection.fromConnectionRow(row);
    _connections[k] = conn;
    return conn;
  }

  /// Creates (or replaces) a [RedisConnection] for [role] (default stats).
  /// The other role for this id is left alone.
  RedisConnection createConnection(
    ConnectionRow row, {
    RedisSessionRole role = RedisSessionRole.stats,
  }) {
    if (row.type != 'redis') {
      throw ArgumentError('Connection type must be redis');
    }

    final id = row.id ?? 0;
    final k = _key(id, role);

    final existing = _connections.remove(k);
    if (existing != null) {
      unawaited(existing.disconnect());
    }

    final conn = RedisConnection.fromConnectionRow(row);
    _connections[k] = conn;
    return conn;
  }

  RedisConnection? getConnection(
    int id, {
    RedisSessionRole role = RedisSessionRole.stats,
  }) =>
      _connections[_key(id, role)];

  Future<void> connect(RedisConnection connection) async {
    await connection.connect();
  }

  /// Drops [connection] from the pool immediately, then awaits the TCP close.
  Future<void> disconnect(RedisConnection connection) async {
    _connections.removeWhere((_, c) => identical(c, connection));
    await connection.disconnect();
  }

  /// Awaits close of every role for [id] (user Disconnect).
  Future<void> disconnectByConnectionId(int id) async {
    for (final role in RedisSessionRole.values) {
      final conn = _connections.remove(_key(id, role));
      if (conn != null) await conn.disconnect();
    }
  }

  /// Disconnects all Redis connections (e.g. app shutdown).
  Future<void> disconnectAll() async {
    final all = _connections.values.toList();
    _connections.clear();
    for (final connection in all) {
      await connection.disconnect();
    }
  }
}
