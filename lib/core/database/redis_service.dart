import '../storage/local_db.dart';
import 'redis_connection.dart';

/// Service for Redis connections (Dart redis package, no Java).
class RedisService {
  RedisService._();
  static final RedisService instance = RedisService._();

  final Map<int, RedisConnection> _connections = {};

  /// Creates (or replaces) a [RedisConnection] for the given [ConnectionRow].
  /// If a connection with the same ID already exists it is disconnected first.
  RedisConnection createConnection(ConnectionRow row) {
    if (row.type != 'redis') {
      throw ArgumentError('Connection type must be redis');
    }

    final id = row.id ?? 0;

    // Disconnect previous connection for this ID, if any.
    final existing = _connections[id];
    if (existing != null) {
      existing.disconnect(); // fire-and-forget; disconnect is safe
    }

    final conn = RedisConnection(
      id: id,
      name: row.name,
      host: row.host ?? 'localhost',
      port: row.port ?? 6379,
      username: row.username,
      password: row.password,
    );
    _connections[id] = conn;
    return conn;
  }

  RedisConnection? getConnection(int id) => _connections[id];

  Future<void> connect(RedisConnection connection) async {
    await connection.connect();
  }

  Future<void> disconnect(RedisConnection connection) async {
    await connection.disconnect();
    _connections.remove(connection.id);
  }
}
