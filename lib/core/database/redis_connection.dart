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
    _isConnected = false;
    _command = null;
    final c = _conn;
    _conn = null;
    try {
      await c?.close();
    } catch (_) {
      // Connection may already be closed — ignore.
    }
  }

  Future<String> info() async {
    if (!isConnected || _command == null) {
      throw StateError('Not connected to Redis');
    }
    final result = await _command!.send_object(['INFO']);
    return result?.toString() ?? '';
  }

  /// Send an arbitrary command and return the raw result.
  Future<dynamic> sendCommand(List<dynamic> args) async {
    if (!isConnected || _command == null) {
      throw StateError('Not connected to Redis');
    }
    return _command!.send_object(args);
  }

  /// SELECT a database by index.
  Future<void> select(int db) async {
    await sendCommand(['SELECT', db.toString()]);
  }

  /// SCAN keys with optional pattern. Returns `(cursor, keys)`.
  Future<(String, List<String>)> scan(
    String cursor, {
    String? pattern,
    int count = 100,
  }) async {
    final args = <dynamic>['SCAN', cursor];
    if (pattern != null && pattern.isNotEmpty) {
      args.addAll(['MATCH', pattern]);
    }
    args.addAll(['COUNT', count.toString()]);
    final result = await sendCommand(args);
    if (result is List && result.length == 2) {
      final nextCursor = result[0].toString();
      final keys = (result[1] as List).map((e) => e.toString()).toList();
      return (nextCursor, keys);
    }
    return ('0', <String>[]);
  }

  /// GET a string value.
  Future<String?> get(String key) async {
    final result = await sendCommand(['GET', key]);
    return result?.toString();
  }

  /// SET a string value.
  Future<void> set(String key, String value) async {
    await sendCommand(['SET', key, value]);
  }

  /// DEL one or more keys.
  Future<int> del(List<String> keys) async {
    final result = await sendCommand(['DEL', ...keys]);
    return int.tryParse(result.toString()) ?? 0;
  }

  /// TYPE of a key.
  Future<String> type(String key) async {
    final result = await sendCommand(['TYPE', key]);
    return result.toString();
  }

  /// TTL of a key in seconds (-1 = no expiry, -2 = key missing).
  Future<int> ttl(String key) async {
    final result = await sendCommand(['TTL', key]);
    return int.tryParse(result.toString()) ?? -2;
  }

  /// EXPIRE — set TTL in seconds.
  Future<void> expire(String key, int seconds) async {
    await sendCommand(['EXPIRE', key, seconds.toString()]);
  }

  /// PERSIST — remove TTL.
  Future<void> persist(String key) async {
    await sendCommand(['PERSIST', key]);
  }

  /// HGETALL — returns map of field:value.
  Future<Map<String, String>> hgetall(String key) async {
    final result = await sendCommand(['HGETALL', key]);
    final map = <String, String>{};
    if (result is List) {
      for (var i = 0; i + 1 < result.length; i += 2) {
        map[result[i].toString()] = result[i + 1].toString();
      }
    }
    return map;
  }

  /// HSET a field.
  Future<void> hset(String key, String field, String value) async {
    await sendCommand(['HSET', key, field, value]);
  }

  /// HDEL a field.
  Future<void> hdel(String key, String field) async {
    await sendCommand(['HDEL', key, field]);
  }

  /// LRANGE — list slice.
  Future<List<String>> lrange(String key, int start, int stop) async {
    final result = await sendCommand(['LRANGE', key, start.toString(), stop.toString()]);
    if (result is List) return result.map((e) => e.toString()).toList();
    return [];
  }

  /// LLEN — list length.
  Future<int> llen(String key) async {
    final result = await sendCommand(['LLEN', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  /// RPUSH — append to list.
  Future<void> rpush(String key, String value) async {
    await sendCommand(['RPUSH', key, value]);
  }

  /// SMEMBERS — set members.
  Future<List<String>> smembers(String key) async {
    final result = await sendCommand(['SMEMBERS', key]);
    if (result is List) return result.map((e) => e.toString()).toList();
    return [];
  }

  /// SADD — add to set.
  Future<void> sadd(String key, String value) async {
    await sendCommand(['SADD', key, value]);
  }

  /// SREM — remove from set.
  Future<void> srem(String key, String value) async {
    await sendCommand(['SREM', key, value]);
  }

  /// ZRANGE with scores (WITHSCORES). Returns list of (member, score).
  Future<List<(String, double)>> zrangeWithScores(String key, int start, int stop) async {
    final result = await sendCommand(['ZRANGE', key, start.toString(), stop.toString(), 'WITHSCORES']);
    final list = <(String, double)>[];
    if (result is List) {
      for (var i = 0; i + 1 < result.length; i += 2) {
        list.add((result[i].toString(), double.tryParse(result[i + 1].toString()) ?? 0));
      }
    }
    return list;
  }

  /// ZCARD — sorted set cardinality.
  Future<int> zcard(String key) async {
    final result = await sendCommand(['ZCARD', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  /// ZADD — add to sorted set.
  Future<void> zadd(String key, double score, String member) async {
    await sendCommand(['ZADD', key, score.toString(), member]);
  }

  /// ZREM — remove from sorted set.
  Future<void> zrem(String key, String member) async {
    await sendCommand(['ZREM', key, member]);
  }

  /// RENAME a key.
  Future<void> rename(String oldKey, String newKey) async {
    await sendCommand(['RENAME', oldKey, newKey]);
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
