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

  // ─── Data commands ─────────────────────────────────────────────────────

  /// Raw command helper.
  Future<dynamic> sendCommand(List<dynamic> args) async {
    if (!isConnected || _command == null) {
      throw StateError('Not connected to Redis');
    }
    return _command!.send_object(args);
  }

  /// SELECT database index.
  Future<void> selectDatabase(int db) async {
    await sendCommand(['SELECT', db]);
  }

  /// DBSIZE — number of keys in the currently selected database.
  Future<int> dbSize() async {
    final result = await sendCommand(['DBSIZE']);
    return result is int ? result : int.tryParse(result.toString()) ?? 0;
  }

  /// CONFIG GET databases — max number of databases.
  Future<int> getMaxDatabases() async {
    try {
      final result = await sendCommand(['CONFIG', 'GET', 'databases']);
      if (result is List && result.length >= 2) {
        return int.tryParse(result[1].toString()) ?? 16;
      }
    } catch (_) {
      // Some Redis instances don't allow CONFIG; fall back.
    }
    return 16;
  }

  /// SCAN cursor [MATCH pattern] [COUNT count].
  /// Returns (nextCursor, keys).
  Future<(int, List<String>)> scan({
    int cursor = 0,
    String? match,
    int count = 100,
  }) async {
    final args = <dynamic>['SCAN', cursor];
    if (match != null && match.isNotEmpty) {
      args.addAll(['MATCH', match]);
    }
    args.addAll(['COUNT', count]);
    final result = await sendCommand(args);
    if (result is List && result.length == 2) {
      final nextCursor = int.tryParse(result[0].toString()) ?? 0;
      final keys = (result[1] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      return (nextCursor, keys);
    }
    return (0, <String>[]);
  }

  /// TYPE key.
  Future<String> keyType(String key) async {
    final result = await sendCommand(['TYPE', key]);
    return result?.toString() ?? 'none';
  }

  /// TTL key (returns -1 if no expiry, -2 if missing).
  Future<int> ttl(String key) async {
    final result = await sendCommand(['TTL', key]);
    return result is int ? result : int.tryParse(result.toString()) ?? -1;
  }

  /// GET (string).
  Future<String?> get(String key) async {
    final result = await sendCommand(['GET', key]);
    return result?.toString();
  }

  /// SET key value [EX seconds].
  Future<void> set(String key, String value, {int? ttlSeconds}) async {
    if (ttlSeconds != null && ttlSeconds > 0) {
      await sendCommand(['SET', key, value, 'EX', ttlSeconds]);
    } else {
      await sendCommand(['SET', key, value]);
    }
  }

  /// HGETALL key. Returns a `Map<String, String>`.
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

  /// HSET key field value.
  Future<void> hset(String key, String field, String value) async {
    await sendCommand(['HSET', key, field, value]);
  }

  /// HDEL key field.
  Future<void> hdel(String key, String field) async {
    await sendCommand(['HDEL', key, field]);
  }

  /// LRANGE key start stop.
  Future<List<String>> lrange(String key, int start, int stop) async {
    final result = await sendCommand(['LRANGE', key, start, stop]);
    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }
    return [];
  }

  /// LLEN key.
  Future<int> llen(String key) async {
    final result = await sendCommand(['LLEN', key]);
    return result is int ? result : int.tryParse(result.toString()) ?? 0;
  }

  /// RPUSH key value.
  Future<void> rpush(String key, String value) async {
    await sendCommand(['RPUSH', key, value]);
  }

  /// SMEMBERS key.
  Future<List<String>> smembers(String key) async {
    final result = await sendCommand(['SMEMBERS', key]);
    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }
    return [];
  }

  /// SCARD key.
  Future<int> scard(String key) async {
    final result = await sendCommand(['SCARD', key]);
    return result is int ? result : int.tryParse(result.toString()) ?? 0;
  }

  /// SADD key member.
  Future<void> sadd(String key, String member) async {
    await sendCommand(['SADD', key, member]);
  }

  /// SREM key member.
  Future<void> srem(String key, String member) async {
    await sendCommand(['SREM', key, member]);
  }

  /// ZRANGE key start stop WITHSCORES → list of (member, score).
  Future<List<(String, double)>> zrangeWithScores(
      String key, int start, int stop) async {
    final result =
        await sendCommand(['ZRANGE', key, start, stop, 'WITHSCORES']);
    final list = <(String, double)>[];
    if (result is List) {
      for (var i = 0; i + 1 < result.length; i += 2) {
        final member = result[i].toString();
        final score = double.tryParse(result[i + 1].toString()) ?? 0;
        list.add((member, score));
      }
    }
    return list;
  }

  /// ZCARD key.
  Future<int> zcard(String key) async {
    final result = await sendCommand(['ZCARD', key]);
    return result is int ? result : int.tryParse(result.toString()) ?? 0;
  }

  /// ZADD key score member.
  Future<void> zadd(String key, double score, String member) async {
    await sendCommand(['ZADD', key, score, member]);
  }

  /// ZREM key member.
  Future<void> zrem(String key, String member) async {
    await sendCommand(['ZREM', key, member]);
  }

  /// DEL key.
  Future<int> del(String key) async {
    final result = await sendCommand(['DEL', key]);
    return result is int ? result : int.tryParse(result.toString()) ?? 0;
  }

  /// RENAME old new.
  Future<void> rename(String oldKey, String newKey) async {
    await sendCommand(['RENAME', oldKey, newKey]);
  }

  /// EXPIRE key seconds.
  Future<void> expire(String key, int seconds) async {
    await sendCommand(['EXPIRE', key, seconds]);
  }

  /// PERSIST key (remove TTL).
  Future<void> persist(String key) async {
    await sendCommand(['PERSIST', key]);
  }

  /// STRLEN / LLEN / SCARD / ZCARD / HLEN — get size for any type.
  Future<int> keySize(String key, String type) async {
    switch (type) {
      case 'string':
        final r = await sendCommand(['STRLEN', key]);
        return r is int ? r : int.tryParse(r.toString()) ?? 0;
      case 'list':
        return llen(key);
      case 'set':
        return scard(key);
      case 'zset':
        return zcard(key);
      case 'hash':
        final r = await sendCommand(['HLEN', key]);
        return r is int ? r : int.tryParse(r.toString()) ?? 0;
      default:
        return 0;
    }
  }
}

/// In-memory stub for widget tests (no socket). Handles SELECT, DBSIZE, SCAN,
/// TYPE, TTL used by [RedisKeysView].
class RedisConnectionTestFake extends RedisConnection {
  RedisConnectionTestFake({
    this.firstScanKeys = const ['alpha', 'beta'],
    this.secondScanKeys = const <String>[],
    this.dbSizeResult = 2,
  }) : super(id: -1, name: 'test-fake', host: 'localhost', port: 6379);

  final List<String> firstScanKeys;
  final List<String> secondScanKeys;
  final int dbSizeResult;

  bool _firstScanDone = false;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    _isConnected = true;
    _conn = null;
    _command = null;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    final c = _conn;
    _conn = null;
    _command = null;
    try {
      await c?.close();
    } catch (_) {}
  }

  @override
  Future<dynamic> sendCommand(List<dynamic> args) async {
    if (!_isConnected) {
      throw StateError('Not connected to Redis');
    }
    final op = args.first.toString().toUpperCase();
    switch (op) {
      case 'SELECT':
        return 'OK';
      case 'DBSIZE':
        return dbSizeResult;
      case 'SCAN':
        final cursor = int.tryParse(args[1].toString()) ?? 0;
        if (cursor == 0 && !_firstScanDone) {
          _firstScanDone = true;
          final next = secondScanKeys.isNotEmpty ? 1 : 0;
          return [next, firstScanKeys];
        }
        if (cursor == 1 && secondScanKeys.isNotEmpty) {
          return [0, secondScanKeys];
        }
        return [0, <String>[]];
      case 'TYPE':
        return 'string';
      case 'TTL':
        return -1;
      default:
        return null;
    }
  }
}

class RedisConnectionException implements Exception {
  RedisConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}
