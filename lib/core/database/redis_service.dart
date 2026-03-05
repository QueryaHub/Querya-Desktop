import '../storage/local_db.dart';
import 'redis_connection.dart';

/// Service for Redis connections (Dart redis package, no Java).
class RedisService {
  RedisService._();
  static final RedisService instance = RedisService._();

  final Map<int, RedisConnection> _connections = {};

  RedisConnection createConnection(ConnectionRow row) {
    if (row.type != 'redis') {
      throw ArgumentError('Connection type must be redis');
    }
    final conn = RedisConnection(
      id: row.id ?? 0,
      name: row.name,
      host: row.host ?? 'localhost',
      port: row.port ?? 6379,
      username: row.username,
      password: row.password,
    );
    _connections[conn.id] = conn;
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
