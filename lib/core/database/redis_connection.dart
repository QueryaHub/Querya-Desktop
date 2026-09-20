import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/security/ssl_certificate_support.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:redis/redis.dart' as redis;

/// First page / load-more size for hash, list, set, and zset editors.
const redisCollectionPageSize = 200;

/// Warn in the key editor when HLEN / LLEN / SCARD / ZCARD is at least this.
const redisLargeCollectionWarnAt = 10000;

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
    _command!.setParser(redis.RedisParserBulkBinary());
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
    return RedisBulkValue.fromReply(result).text ?? '';
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
    return redisReplyInt(result);
  }

  /// CONFIG GET databases — max number of databases.
  Future<int> getMaxDatabases() async {
    try {
      final result = await sendCommand(['CONFIG', 'GET', 'databases']);
      if (result is List && result.length >= 2) {
        return redisReplyInt(result[1], 16);
      }
    } catch (e) {
      debugPrint('RedisConnection.getMaxDatabases: $e');
      // Some Redis instances don't allow CONFIG; fall back.
    }
    return 16;
  }

  /// SCAN cursor [MATCH pattern] [COUNT count].
  /// Returns (nextCursor, keys).
  Future<(int, List<RedisBulkValue>)> scan({
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
      final nextCursor = redisReplyInt(result[0]);
      final keys =
          (result[1] as List?)?.map(RedisBulkValue.fromReply).toList() ?? [];
      return (nextCursor, keys);
    }
    return (0, <RedisBulkValue>[]);
  }

  /// TYPE key.
  Future<String> keyType(Object key) async {
    final result = await sendCommand(['TYPE', redisCommandArg(key)]);
    return RedisBulkValue.fromReply(result).text ?? 'none';
  }

  /// TTL key (returns -1 if no expiry, -2 if missing).
  Future<int> ttl(Object key) async {
    final result = await sendCommand(['TTL', redisCommandArg(key)]);
    return redisReplyInt(result, -1);
  }

  /// Pipelined TYPE + TTL for a SCAN batch.
  ///
  /// Writes all commands before awaiting replies (redis-dart FIFO parse
  /// queue + optional Nagle via [Command.pipe_start]), so a batch of N keys
  /// costs ~1 RTT instead of ~2N sequential round-trips.
  Future<List<({String type, int ttl})>> typesAndTtls(
      List<RedisBulkValue> keys) async {
    if (keys.isEmpty) return const [];
    if (!isConnected) {
      throw StateError('Not connected to Redis');
    }

    final cmd = _command;
    cmd?.pipe_start();
    try {
      final typeFutures = <Future<String>>[
        for (final key in keys)
          sendCommand(['TYPE', key.commandArg]).then(
            (v) => RedisBulkValue.fromReply(v).text ?? 'none',
            onError: (_) => 'unknown',
          ),
      ];
      final ttlFutures = <Future<int>>[
        for (final key in keys)
          sendCommand(['TTL', key.commandArg]).then(
            (v) => redisReplyInt(v, -1),
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

  /// GET. Returns null for a missing key. Non-UTF-8 values keep raw bytes.
  Future<RedisBulkValue?> get(Object key) async {
    final result = await sendCommand(['GET', redisCommandArg(key)]);
    if (result == null) return null;
    return RedisBulkValue.fromReply(result);
  }

  /// SET key value [EX seconds].
  ///
  /// When [ttlSeconds] is omitted and [keepTtl] is true (the default), the
  /// existing expiry is kept (`KEEPTTL`, Redis 6+). Falls back to `TTL` then
  /// `SET … EX` on older servers. Does not recreate a key that is already gone
  /// (TTL `-2` / `XX` miss).
  Future<void> set(
    Object key,
    String value, {
    int? ttlSeconds,
    bool keepTtl = true,
  }) async {
    _assertWritable();
    final k = redisCommandArg(key);
    if (ttlSeconds != null && ttlSeconds > 0) {
      await sendCommand(['SET', k, value, 'EX', ttlSeconds]);
      return;
    }
    if (!keepTtl) {
      await sendCommand(['SET', k, value]);
      return;
    }
    await _setPreservingTtl(k, value);
  }

  Future<void> _setPreservingTtl(Object key, String value) async {
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

  /// HGETALL key.
  Future<Map<RedisBulkValue, RedisBulkValue>> hgetall(Object key) async {
    final result = await sendCommand(['HGETALL', redisCommandArg(key)]);
    final map = <RedisBulkValue, RedisBulkValue>{};
    if (result is List) {
      for (var i = 0; i + 1 < result.length; i += 2) {
        map[RedisBulkValue.fromReply(result[i])] =
            RedisBulkValue.fromReply(result[i + 1]);
      }
    }
    return map;
  }

  /// HSCAN key cursor [COUNT count]. Returns (nextCursor, fields).
  Future<(int, Map<RedisBulkValue, RedisBulkValue>)> hscan(
    Object key, {
    int cursor = 0,
    int count = redisCollectionPageSize,
  }) async {
    final result = await sendCommand(
        ['HSCAN', redisCommandArg(key), cursor, 'COUNT', count]);
    if (result is List && result.length == 2) {
      final nextCursor = redisReplyInt(result[0]);
      final map = <RedisBulkValue, RedisBulkValue>{};
      final pairs = result[1];
      if (pairs is List) {
        for (var i = 0; i + 1 < pairs.length; i += 2) {
          map[RedisBulkValue.fromReply(pairs[i])] =
              RedisBulkValue.fromReply(pairs[i + 1]);
        }
      }
      return (nextCursor, map);
    }
    return (0, <RedisBulkValue, RedisBulkValue>{});
  }

  /// HLEN key.
  Future<int> hlen(Object key) async {
    final result = await sendCommand(['HLEN', redisCommandArg(key)]);
    return redisReplyInt(result);
  }

  /// HSET key field value.
  Future<void> hset(Object key, String field, String value) async {
    _assertWritable();
    await sendCommand(['HSET', redisCommandArg(key), field, value]);
  }

  /// HDEL key field.
  Future<void> hdel(Object key, Object field) async {
    _assertWritable();
    await sendCommand(['HDEL', redisCommandArg(key), redisCommandArg(field)]);
  }

  /// LRANGE key start stop.
  Future<List<RedisBulkValue>> lrange(Object key, int start, int stop) async {
    final result =
        await sendCommand(['LRANGE', redisCommandArg(key), start, stop]);
    if (result is List) {
      return result.map(RedisBulkValue.fromReply).toList();
    }
    return [];
  }

  /// LLEN key.
  Future<int> llen(Object key) async {
    final result = await sendCommand(['LLEN', redisCommandArg(key)]);
    return redisReplyInt(result);
  }

  /// RPUSH key value.
  Future<void> rpush(Object key, String value) async {
    _assertWritable();
    await sendCommand(['RPUSH', redisCommandArg(key), value]);
  }

  /// SMEMBERS key.
  Future<List<RedisBulkValue>> smembers(Object key) async {
    final result = await sendCommand(['SMEMBERS', redisCommandArg(key)]);
    if (result is List) {
      return result.map(RedisBulkValue.fromReply).toList();
    }
    return [];
  }

  /// SSCAN key cursor [COUNT count]. Returns (nextCursor, members).
  Future<(int, List<RedisBulkValue>)> sscan(
    Object key, {
    int cursor = 0,
    int count = redisCollectionPageSize,
  }) async {
    final result = await sendCommand(
        ['SSCAN', redisCommandArg(key), cursor, 'COUNT', count]);
    if (result is List && result.length == 2) {
      final nextCursor = redisReplyInt(result[0]);
      final members =
          (result[1] as List?)?.map(RedisBulkValue.fromReply).toList() ?? [];
      return (nextCursor, members);
    }
    return (0, <RedisBulkValue>[]);
  }

  /// SCARD key.
  Future<int> scard(Object key) async {
    final result = await sendCommand(['SCARD', redisCommandArg(key)]);
    return redisReplyInt(result);
  }

  /// SADD key member.
  Future<void> sadd(Object key, String member) async {
    _assertWritable();
    await sendCommand(['SADD', redisCommandArg(key), member]);
  }

  /// SREM key member.
  Future<void> srem(Object key, Object member) async {
    _assertWritable();
    await sendCommand(['SREM', redisCommandArg(key), redisCommandArg(member)]);
  }

  /// ZRANGE key start stop WITHSCORES → list of (member, score).
  Future<List<(RedisBulkValue, double)>> zrangeWithScores(
      Object key, int start, int stop) async {
    final result = await sendCommand(
        ['ZRANGE', redisCommandArg(key), start, stop, 'WITHSCORES']);
    final list = <(RedisBulkValue, double)>[];
    if (result is List) {
      for (var i = 0; i + 1 < result.length; i += 2) {
        list.add((
          RedisBulkValue.fromReply(result[i]),
          redisReplyDouble(result[i + 1]),
        ));
      }
    }
    return list;
  }

  /// ZCARD key.
  Future<int> zcard(Object key) async {
    final result = await sendCommand(['ZCARD', redisCommandArg(key)]);
    return redisReplyInt(result);
  }

  /// ZADD key score member.
  Future<void> zadd(Object key, double score, String member) async {
    _assertWritable();
    await sendCommand(['ZADD', redisCommandArg(key), score, member]);
  }

  /// ZREM key member.
  Future<void> zrem(Object key, Object member) async {
    _assertWritable();
    await sendCommand(['ZREM', redisCommandArg(key), redisCommandArg(member)]);
  }

  /// DEL key.
  Future<int> del(Object key) async {
    _assertWritable();
    final result = await sendCommand(['DEL', redisCommandArg(key)]);
    return redisReplyInt(result);
  }

  /// RENAME old new.
  Future<void> rename(String oldKey, String newKey) async {
    _assertWritable();
    await sendCommand(['RENAME', oldKey, newKey]);
  }

  /// EXPIRE key seconds.
  Future<void> expire(Object key, int seconds) async {
    _assertWritable();
    await sendCommand(['EXPIRE', redisCommandArg(key), seconds]);
  }

  /// PERSIST key (remove TTL).
  Future<void> persist(Object key) async {
    _assertWritable();
    await sendCommand(['PERSIST', redisCommandArg(key)]);
  }

  /// STRLEN / LLEN / SCARD / ZCARD / HLEN — get size for any type.
  Future<int> keySize(Object key, String type) async {
    switch (type) {
      case 'string':
        final r = await sendCommand(['STRLEN', redisCommandArg(key)]);
        return redisReplyInt(r);
      case 'list':
        return llen(key);
      case 'set':
        return scard(key);
      case 'zset':
        return zcard(key);
      case 'hash':
        return hlen(key);
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
    this.listItems = const <String>[],
    this.llenResult,
    this.hashFirstPage = const <String, String>{},
    this.hashSecondPage = const <String, String>{},
    this.hlenResult,
    this.setFirstPage = const <String>[],
    this.setSecondPage = const <String>[],
    this.scardResult,
    this.zsetItems = const <(String, double)>[],
    this.zcardResult,
    this.typeResult = 'string',
    this.failType = false,
    this.getBytesResult,
    this.binaryScanKeys = const <List<int>>[],
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
  final List<String> listItems;
  final int? llenResult;
  final Map<String, String> hashFirstPage;
  final Map<String, String> hashSecondPage;
  final int? hlenResult;
  final List<String> setFirstPage;
  final List<String> setSecondPage;
  final int? scardResult;
  final List<(String, double)> zsetItems;
  final int? zcardResult;
  final String typeResult;
  final bool failType;
  final List<int>? getBytesResult;
  final List<List<int>> binaryScanKeys;
  final List<String> sentCommands = [];

  bool _firstScanDone = false;
  bool _firstHscanDone = false;
  bool _firstSscanDone = false;

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
    sentCommands.add(op);
    switch (op) {
      case 'SELECT':
        return 'OK';
      case 'DBSIZE':
        return dbSizeResult;
      case 'SCAN':
        final cursor = int.tryParse(args[1].toString()) ?? 0;
        List<Object> keysFor(List<String> named) =>
            [...named, ...binaryScanKeys];
        if (cursor == 0 && !_firstScanDone) {
          _firstScanDone = true;
          final next = secondScanKeys.isNotEmpty ? 1 : 0;
          return [next, keysFor(firstScanKeys)];
        }
        if (cursor == 1 && secondScanKeys.isNotEmpty) {
          return [0, keysFor(secondScanKeys)];
        }
        return [0, <Object>[]];
      case 'TYPE':
        if (failType) {
          throw StateError('TYPE failed');
        }
        return typeResult;
      case 'TTL':
        return -1;
      case 'GET':
        if (getBytesResult != null) return getBytesResult;
        if (typeResult != 'string') {
          throw StateError(
            'WRONGTYPE Operation against a key holding the wrong kind of value',
          );
        }
        return getResult;
      case 'SET':
        if (typeResult != 'string') {
          throw StateError('SET refused: key is $typeResult');
        }
        return 'OK';
      case 'HGETALL':
      case 'SMEMBERS':
        throw StateError('$op is unbounded; use a paged command');
      case 'HLEN':
        return hlenResult ?? hashFirstPage.length + hashSecondPage.length;
      case 'LLEN':
        return llenResult ?? listItems.length;
      case 'SCARD':
        return scardResult ?? setFirstPage.length + setSecondPage.length;
      case 'ZCARD':
        return zcardResult ?? zsetItems.length;
      case 'LRANGE':
        return _sliceList(listItems, args);
      case 'ZRANGE':
        final stop = int.tryParse(args[3].toString()) ?? -1;
        if (stop < 0) {
          throw StateError('unbounded ZRANGE');
        }
        final start = int.tryParse(args[2].toString()) ?? 0;
        if (start >= zsetItems.length || start > stop) return <dynamic>[];
        final end = (stop + 1).clamp(0, zsetItems.length);
        final out = <dynamic>[];
        for (final (member, score) in zsetItems.sublist(start, end)) {
          out.add(member);
          out.add(score);
        }
        return out;
      case 'HSCAN':
        return _pagedPairs(
          cursor: int.tryParse(args[2].toString()) ?? 0,
          first: hashFirstPage,
          second: hashSecondPage,
          firstDone: _firstHscanDone,
          markFirst: () => _firstHscanDone = true,
        );
      case 'SSCAN':
        final cursor = int.tryParse(args[2].toString()) ?? 0;
        if (cursor == 0 && !_firstSscanDone) {
          _firstSscanDone = true;
          final next = setSecondPage.isNotEmpty ? 1 : 0;
          return [next, setFirstPage];
        }
        if (cursor == 1 && setSecondPage.isNotEmpty) {
          return [0, setSecondPage];
        }
        return [0, <String>[]];
      case 'READONLY':
      case 'READWRITE':
        return 'OK';
      default:
        return null;
    }
  }

  List<String> _sliceList(List<String> items, List<dynamic> args) {
    if (items.isEmpty) return const [];
    final start = int.tryParse(args[2].toString()) ?? 0;
    var stop = int.tryParse(args[3].toString()) ?? -1;
    if (stop < 0) {
      throw StateError('unbounded LRANGE');
    }
    if (start >= items.length || start > stop) return const [];
    final end = (stop + 1).clamp(0, items.length);
    return items.sublist(start, end);
  }

  List<dynamic> _pagedPairs({
    required int cursor,
    required Map<String, String> first,
    required Map<String, String> second,
    required bool firstDone,
    required void Function() markFirst,
  }) {
    List<String> flatten(Map<String, String> map) {
      final out = <String>[];
      map.forEach((k, v) {
        out.add(k);
        out.add(v);
      });
      return out;
    }

    if (cursor == 0 && !firstDone) {
      markFirst();
      final next = second.isNotEmpty ? 1 : 0;
      return [next, flatten(first)];
    }
    if (cursor == 1 && second.isNotEmpty) {
      return [0, flatten(second)];
    }
    return [0, <String>[]];
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
