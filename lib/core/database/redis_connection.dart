import 'package:redis/redis.dart' as redis;

/// Redis connection using the Dart redis package (no Java/JRE).
class RedisConnection {
  RedisConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 6379,
    this.username,
    this.password,
  });

  final int id;
  final String name;
  final String host;
  final int port;
  final String? username;
  final String? password;

  redis.RedisConnection? _conn;
  redis.Command? _command;
  bool _isConnected = false;

  bool get isConnected => _isConnected && _command != null;

  Future<void> connect() async {
    if (_isConnected && _command != null) return;
    _conn = redis.RedisConnection();
    _command = await _conn!.connect(host, port);
    if (password != null && password!.isNotEmpty) {
      if (username != null && username!.trim().isNotEmpty) {
        await _command!.send_object(['AUTH', username!.trim(), password!]);
      } else {
        await _command!.send_object(['AUTH', password]);
      }
    }
    final result = await _command!.send_object(['PING']);
    if (result == null || result.toString().toUpperCase() != 'PONG') {
      await _conn?.close();
      _conn = null;
      _command = null;
      throw RedisConnectionException('PING failed');
    }
    _isConnected = true;
  }

  Future<void> disconnect() async {
    await _conn?.close();
    _conn = null;
    _command = null;
    _isConnected = false;
  }

  Future<String> info() async {
    if (!isConnected || _command == null) {
      throw StateError('Not connected to Redis');
    }
    final result = await _command!.send_object(['INFO']);
    return result?.toString() ?? '';
  }

  Future<bool> testConnection() async {
    try {
      await connect();
      return true;
    } catch (_) {
      return false;
    } finally {
      await disconnect();
    }
  }
}

class RedisConnectionException implements Exception {
  RedisConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}
