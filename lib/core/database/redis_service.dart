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

  /// Keys view and key editor of one database: SCAN/GET/SET/DEL.
  explorer,

  /// The CLI console. Its own socket, so a `SELECT` typed there moves only
  /// the console and not the explorer next to it (#1569).
  cli,
}

/// Service for Redis connections (Dart redis package, no Java).
class RedisService {
  RedisService._();
  static final RedisService instance = RedisService._();

  final Map<String, RedisConnection> _connections = {};

  /// One socket per connection, role and database. A socket never switches
  /// database for a view, so a command cannot land in another view's database
  /// between a `SELECT` and the command (#1569).
  String _key(int id, RedisSessionRole role, int database) =>
      '$id::${role.name}::$database';

  /// Returns the existing socket for [role] and [database], or creates one
  /// without touching the others.
  RedisConnection acquire(
    ConnectionRow row, {
    required RedisSessionRole role,
    int database = 0,
  }) {
    if (row.type != 'redis') {
      throw ArgumentError('Connection type must be redis');
    }
    final id = row.id ?? 0;
    final k = _key(id, role, database);
    final existing = _connections[k];
    if (existing != null) return existing;
    final conn = RedisConnection.fromConnectionRow(row)..database = database;
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
    final k = _key(id, role, 0);

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
    int database = 0,
  }) =>
      _connections[_key(id, role, database)];

  Future<void> connect(RedisConnection connection) async {
    await connection.connect();
  }

  /// Drops [connection] from the pool immediately, then awaits the TCP close.
  Future<void> disconnect(RedisConnection connection) async {
    _connections.removeWhere((_, c) => identical(c, connection));
    await connection.disconnect();
  }

  /// Awaits close of every role and database for [id] (user Disconnect).
  Future<void> disconnectByConnectionId(int id) async {
    final prefix = '$id::';
    final keys = [
      for (final k in _connections.keys)
        if (k.startsWith(prefix)) k,
    ];
    for (final k in keys) {
      final conn = _connections.remove(k);
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
