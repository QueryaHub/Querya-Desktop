import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/security/ssl_certificate_support.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:redis/redis.dart' as redis;

/// Redis connection using the Dart redis package (no Java/JRE).
class RedisConnection {
  RedisConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 6379,
    this.username,
    String? password,
    this.useSSL = false,
    String? connectionString,
  })  : _password = password,
        _connectionString = connectionString;

  /// Parses [ConnectionRow.connectionString] (`redis://` / `rediss://`) for
  /// host, port, userinfo, and TLS. Pass [id] `-1` for a sidebar probe that
  /// must not share the workspace pool id (and skips secrets lookup).
  factory RedisConnection.fromConnectionRow(
    ConnectionRow row, {
    int? id,
  }) {
    final resolvedId = id ?? row.id ?? 0;
    final uriText = row.connectionString?.trim();
    if (uriText != null && uriText.isNotEmpty) {
      final parsed = Uri.parse(uriText);
      final info = parsed.userInfo;
      String? user;
      String? pass;
      if (info.isNotEmpty) {
        final colon = info.indexOf(':');
        if (colon >= 0) {
          user = Uri.decodeComponent(info.substring(0, colon));
          pass = Uri.decodeComponent(info.substring(colon + 1));
        } else {
          user = Uri.decodeComponent(info);
        }
      }
      return RedisConnection(
        id: resolvedId,
        name: row.name,
        host: parsed.host.isEmpty ? (row.host ?? 'localhost') : parsed.host,
        port: parsed.hasPort ? parsed.port : (row.port ?? 6379),
        username: user ?? row.username,
        password: pass ?? row.password,
        useSSL: row.useSSL || parsed.scheme == 'rediss',
        connectionString: uriText,
      );
    }
    return RedisConnection(
      id: resolvedId,
      name: row.name,
      host: row.host ?? 'localhost',
      port: row.port ?? 6379,
      username: row.username,
      password: row.password,
      useSSL: row.useSSL,
      connectionString: row.connectionString,
    );
  }

  final int id;
  final String name;
  final String host;
  final int port;
  final String? username;
  String? _password;
  final bool useSSL;
  String? _connectionString;

  String? get password => _password;
  String? get connectionString => _connectionString;

  redis.RedisConnection? _conn;
  redis.Command? _command;
  bool _isConnected = false;

  bool get isConnected => _isConnected && _command != null;

  /// Scrubs sensitive in-memory credentials once the network handshake completes.
  void scrubCredentials() {
    _password = null;
    _connectionString = null;
  }

  Future<void> connect() async {
    if (_isConnected && _command != null) return;

    var effectivePassword = _password;
    var effectiveConnectionString = _connectionString;

    if ((effectivePassword == null || effectivePassword.isEmpty) &&
        (effectiveConnectionString == null ||
            effectiveConnectionString.isEmpty) &&
        id > 0) {
      try {
        final secrets = await ConnectionSecretsStore.readForConnection(id);
        effectivePassword = secrets.password;
        effectiveConnectionString = secrets.connectionString;
      } catch (_) {}
    }

    _conn = redis.RedisConnection();
    final sslPaths =
        extractSslCertificatePathsFromString(effectiveConnectionString);
    final secure = useSSL || sslPaths.hasAny;
    if (secure) {
      final context = buildSecurityContext(sslPaths);
      final socket = await SecureSocket.connect(
        host,
        port,
        context: context,
      );
      _command = await _conn!.connectWithSocket(socket);
    } else {
      _command = await _conn!.connect(host, port);
    }
    if (effectivePassword != null && effectivePassword.isNotEmpty) {
      if (username != null && username!.trim().isNotEmpty) {
        await _command!
            .send_object(['AUTH', username!.trim(), effectivePassword]);
      } else {
        await _command!.send_object(['AUTH', effectivePassword]);
      }
    }
    final result = await _command!.send_object(['PING']);
    if (result == null || result.toString().toUpperCase() != 'PONG') {
      try {
        await _conn?.close();
      } catch (_) {}
      _conn = null;
      _command = null;
      throw RedisConnectionException('PING failed');
    }
    _isConnected = true;
    if (_clientReadOnly) {
      try {
        await _command!.send_object(['READONLY']);
      } catch (_) {
        // Standalone / older servers: READONLY is cluster-replica only.
      }
    }
    scrubCredentials();
  }

  Future<void> disconnect() async {
    final wasConnected = _isConnected;
    _isConnected = false;
    _command = null;
    final c = _conn;
    _conn = null;
    if (c != null && wasConnected) {
      try {
        await c.close();
      } catch (e) {
        if (e is! TypeError && !e.toString().contains('Null check operator')) {
          debugPrint('RedisConnection.disconnect: $e');
        }
      }
    }
  }

  Future<void> forceClose() => disconnect();

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
    } catch (e) {
      debugPrint('RedisConnection.testConnection: $e');
      return false;
    } finally {
      await disconnect();
    }
  }

  // ─── Data commands ─────────────────────────────────────────────────────

  bool _clientReadOnly = false;

  /// Title-bar / session lock. Write helpers throw; [connect] may send
  /// `READONLY` (Redis Cluster replica; ignored or missing on standalone).
  bool get clientReadOnly => _clientReadOnly;

  /// Sets the local write lock and, when already connected, sends
  /// `READONLY` / `READWRITE`. Errors from older servers are ignored.
  Future<void> applyClientReadOnly(bool readOnly) async {
    _clientReadOnly = readOnly;
    if (!isConnected) return;
    try {
      await sendCommand([readOnly ? 'READONLY' : 'READWRITE']);
    } catch (_) {}
  }

  void _assertWritable() {
    if (_clientReadOnly) {
      throw StateError('Redis connection is read-only');
    }
  }

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
    } catch (e) {
      debugPrint('RedisConnection.getMaxDatabases: $e');
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
      final keys =
          (result[1] as List?)?.map((e) => e.toString()).toList() ?? [];
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

  /// Pipelined TYPE + TTL for a SCAN batch.
  ///
  /// Writes all commands before awaiting replies (redis-dart FIFO parse
  /// queue + optional Nagle via [Command.pipe_start]), so a batch of N keys
  /// costs ~1 RTT instead of ~2N sequential round-trips.
  Future<List<({String type, int ttl})>> typesAndTtls(List<String> keys) async {
    if (keys.isEmpty) return const [];
    if (!isConnected) {
      throw StateError('Not connected to Redis');
    }

    final cmd = _command;
    cmd?.pipe_start();
    try {
      final typeFutures = <Future<String>>[
        for (final key in keys)
          sendCommand(['TYPE', key]).then(
            (v) => v?.toString() ?? 'none',
            onError: (_) => 'unknown',
          ),
      ];
      final ttlFutures = <Future<int>>[
        for (final key in keys)
          sendCommand(['TTL', key]).then(
            (v) => v is int ? v : int.tryParse(v.toString()) ?? -1,
            onError: (_) => -1,
          ),
      ];
      final types = await Future.wait(typeFutures);
      final ttls = await Future.wait(ttlFutures);
      return [
        for (var i = 0; i < keys.length; i++) (type: types[i], ttl: ttls[i]),
      ];
    } finally {
      cmd?.pipe_end();
    }
  }

  /// GET (string).
  Future<String?> get(String key) async {
    final result = await sendCommand(['GET', key]);
    return result?.toString();
  }

  /// SET key value [EX seconds].
  ///
  /// When [ttlSeconds] is omitted and [keepTtl] is true (the default), the
  /// existing expiry is kept (`KEEPTTL`, Redis 6+). Falls back to `TTL` then
  /// `SET … EX` on older servers. Does not recreate a key that is already gone
  /// (TTL `-2` / `XX` miss).
  Future<void> set(
    String key,
    String value, {
    int? ttlSeconds,
    bool keepTtl = true,
  }) async {
    _assertWritable();
    if (ttlSeconds != null && ttlSeconds > 0) {
      await sendCommand(['SET', key, value, 'EX', ttlSeconds]);
      return;
    }
    if (!keepTtl) {
      await sendCommand(['SET', key, value]);
      return;
    }
    await _setPreservingTtl(key, value);
  }

  Future<void> _setPreservingTtl(String key, String value) async {
    try {
      final result = await sendCommand(['SET', key, value, 'KEEPTTL', 'XX']);
      if (_isRedisNil(result)) {
        throw StateError('Key no longer exists');
      }
      return;
    } catch (e) {
      if (e is StateError) rethrow;
      if (!_isKeepTtlUnsupported(e)) rethrow;
    }

    final existingTtl = await ttl(key);
    if (existingTtl == -2) {
      throw StateError('Key no longer exists');
    }
    if (existingTtl > 0) {
      await sendCommand(['SET', key, value, 'EX', existingTtl]);
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
    _assertWritable();
    await sendCommand(['HSET', key, field, value]);
  }

  /// HDEL key field.
  Future<void> hdel(String key, String field) async {
    _assertWritable();
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
    _assertWritable();
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
    _assertWritable();
    await sendCommand(['SADD', key, member]);
  }

  /// SREM key member.
  Future<void> srem(String key, String member) async {
    _assertWritable();
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
    _assertWritable();
    await sendCommand(['ZADD', key, score, member]);
  }

  /// ZREM key member.
  Future<void> zrem(String key, String member) async {
    _assertWritable();
    await sendCommand(['ZREM', key, member]);
  }

  /// DEL key.
  Future<int> del(String key) async {
    _assertWritable();
    final result = await sendCommand(['DEL', key]);
    return result is int ? result : int.tryParse(result.toString()) ?? 0;
  }

  /// RENAME old new.
  Future<void> rename(String oldKey, String newKey) async {
    _assertWritable();
    await sendCommand(['RENAME', oldKey, newKey]);
  }

  /// EXPIRE key seconds.
  Future<void> expire(String key, int seconds) async {
    _assertWritable();
    await sendCommand(['EXPIRE', key, seconds]);
  }

  /// PERSIST key (remove TTL).
  Future<void> persist(String key) async {
    _assertWritable();
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
    this.getResult,
  }) : super(
          id: -1,
          name: 'test-fake',
          host: 'localhost',
          port: 6379,
        );

  final List<String> firstScanKeys;
  final List<String> secondScanKeys;
  final int dbSizeResult;
  final String? getResult;

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
    if (c != null) {
      try {
        await c.close();
      } catch (_) {}
    }
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
      case 'GET':
        return getResult;
      case 'READONLY':
      case 'READWRITE':
        return 'OK';
      default:
        return null;
    }
  }
}

bool _isRedisNil(Object? result) =>
    result == null || result.toString().toLowerCase() == 'null';

bool _isKeepTtlUnsupported(Object error) {
  final s = error.toString().toLowerCase();
  return s.contains('syntax') ||
      s.contains('keepttl') ||
      s.contains('wrong number of arguments');
}

class RedisConnectionException implements Exception {
  RedisConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}
