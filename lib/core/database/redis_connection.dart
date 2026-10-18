import 'dart:async';
import 'dart:math' show min;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:querya_desktop/core/database/ssh_tunnel_host.dart';
import 'package:querya_desktop/core/database/querya_database_exception.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/security/ssl_certificate_support.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/core/database/redis_reply.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:redis/redis.dart' as redis;
import 'package:querya_desktop/core/util/log_ignored.dart';

/// First page / load-more size for hash, list, set, and zset editors.
const redisCollectionPageSize = 200;

/// Warn in the key editor when HLEN / LLEN / SCARD / ZCARD is at least this.
const redisLargeCollectionWarnAt = 10000;

/// Redis connection using the Dart redis package (no Java/JRE).
class RedisConnection with SshTunnelHost {
  RedisConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 6379,
    this.username,
    String? password,
    this.useSSL = false,
    String? connectionString,
    this.sshConfig,
    this.sshSecrets,
    Duration? connectTimeout,
  })  : _connectTimeout = connectTimeout,
        _password = password,
        _connectionString = connectionString;

  /// How long the TCP connect, the TLS handshake and `AUTH` / `PING` may take,
  /// each. The same 10 s as PostgreSQL and MySQL (#1307). [Duration.zero] means
  /// no limit.
  ///
  /// A test seam: widget tests that leave a connect pending when they end
  /// (a view opening a real connection to a closed port) would fail on the
  /// timer the limit creates, so `flutter_test_config.dart` sets it to zero.
  @visibleForTesting
  static Duration defaultConnectTimeout = const Duration(seconds: 10);

  final Duration? _connectTimeout;

  Duration get connectTimeout => _connectTimeout ?? defaultConnectTimeout;

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
        sshConfig: row.sshTunnelConfig,
        sshSecrets: row.sshSecrets,
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
      sshConfig: row.sshTunnelConfig,
      sshSecrets: row.sshSecrets,
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

  @override
  final SshTunnelConfig? sshConfig;
  @override
  final SshTunnelSecrets? sshSecrets;

  String? get password => _password;
  String? get connectionString => _connectionString;

  redis.RedisConnection? _conn;
  redis.Command? _command;
  Socket? _socket;
  bool _isConnected = false;

  bool get isConnected => _isConnected && _command != null;

  /// The database index this socket works in. `SELECT`ed on every (re)connect,
  /// so a socket that drops does not come back in db 0, and moved only by
  /// [selectDatabase]. A socket serves one database: views never `SELECT`
  /// before a command, which was not atomic on a shared socket (#1569).
  int database = 0;

  @visibleForTesting
  void setConnectionForTest({
    redis.RedisConnection? conn,
    redis.Command? command,
    Socket? socket,
    bool isConnected = true,
  }) {
    _conn = conn;
    _command = command;
    _socket = socket;
    _isConnected = isConnected;
  }

  /// Scrubs sensitive in-memory credentials once the network handshake completes.
  void scrubCredentials() {
    _password = null;
    _connectionString = null;
  }

  /// Single-flight: a caller that arrives while an attempt is in progress waits
  /// for that attempt. Without this, two callers opened two sockets and two SSH
  /// tunnels, and the second overwrote the first's connection (#1307).
  Future<void> connect() {
    if (isConnected) return Future<void>.value();
    final inFlight = _connecting;
    if (inFlight != null) return inFlight;
    final attempt = _connectOnce();
    _connecting = attempt;
    return attempt.whenComplete(() {
      if (identical(_connecting, attempt)) _connecting = null;
    });
  }

  Future<void>? _connecting;

  Future<void> _connectOnce() async {
    try {
      await _openConnection();
    } on RedisConnectionException {
      rethrow;
    } catch (e, st) {
      rethrowMappedDatabaseError(e, st, driver: DatabaseDriver.redis);
    }
  }

  Future<void> _openConnection() async {
    if (isConnected) return;
    if (_socket != null) {
      try {
        _socket?.destroy();
      } catch (e) {
        logIgnored('redis_connection', e);
      }
      _socket = null;
      _command = null;
      _conn = null;
    }

    var effectivePassword = _password;
    var effectiveConnectionString = _connectionString;

    if ((effectivePassword == null || effectivePassword.isEmpty) &&
        (effectiveConnectionString == null ||
            effectiveConnectionString.isEmpty) &&
        id > 0) {
      // A store that cannot be read throws (#1303): connecting with no password
      // would be reported as a wrong one.
      final secrets = await ConnectionSecretsStore.readForConnection(id);
      effectivePassword = secrets.password;
      effectiveConnectionString = secrets.connectionString;
    }

    final client = redis.RedisConnection();
    _conn = client;
    // Owned here so that a failed attempt can close it, wherever it failed.
    Socket? socket;
    final sslPaths =
        extractSslCertificatePathsFromString(effectiveConnectionString);
    final secure = useSSL || sslPaths.hasAny;
    final limit = connectTimeout > Duration.zero ? connectTimeout : null;

    try {
      adoptSshTunnel(await openSshTunnel(id: id, host: host, port: port));

      final effectiveHost = sshTunnelHandle?.localHost ?? host;
      final effectivePort = sshTunnelHandle?.localPort ?? port;

      // The socket is opened here, with a timeout, for plain and TLS alike.
      socket = secure
          ? await SecureSocket.connect(
              effectiveHost,
              effectivePort,
              context: buildSecurityContext(sslPaths),
              timeout: limit,
            )
          : await Socket.connect(
              effectiveHost,
              effectivePort,
              timeout: limit,
            );
      _socket = socket;
      final activeSocket = socket;
      // Watches the socket for a drop; the future itself is not awaited.
      unawaited(activeSocket.done.then((_) {
        if (identical(_socket, activeSocket)) {
          _isConnected = false;
        }
      }, onError: (_) {
        if (identical(_socket, activeSocket)) {
          _isConnected = false;
        }
      }));
      final command = await client.connectWithSocket(socket);
      _command = command;
      command.setParser(redis.RedisParserBulkBinary());
      // A server that accepts the TCP connection and then says nothing must
      // not hold the caller either.
      final handshake = _authenticate(command, effectivePassword);
      await (limit == null
          ? handshake
          : handshake.timeout(
              limit,
              onTimeout: () => throw TimeoutException(
                'Redis did not answer within ${limit.inSeconds} s',
              ),
            ));
      if (database != 0) {
        await command.send_object(['SELECT', database]);
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
    } catch (e) {
      _isConnected = false;
      _conn = null;
      _command = null;
      _socket = null;
      // The attempt may have got as far as an open socket (a wrong password,
      // a silent server): close it, or every failed try leaves one behind.
      try {
        socket?.destroy();
      } catch (e) {
        logIgnored('redis_connection', e);
      }
      await releaseSshTunnel();
      rethrow;
    }
  }

  /// `AUTH` when there is a password, then `PING`.
  Future<void> _authenticate(redis.Command command, String? password) async {
    if (password != null && password.isNotEmpty) {
      final user = username?.trim();
      if (user != null && user.isNotEmpty) {
        await command.send_object(['AUTH', user, password]);
      } else {
        await command.send_object(['AUTH', password]);
      }
    }
    final result = await command.send_object(['PING']);
    if (result == null || result.toString().toUpperCase() != 'PONG') {
      throw RedisConnectionException('PING failed');
    }
  }

  Future<void> disconnect() async {
    final wasConnected = _isConnected;
    _isConnected = false;
    _command = null;
    final sock = _socket;
    _socket = null;
    try {
      sock?.destroy();
    } catch (e) {
      logIgnored('redis_connection', e);
    }
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
    await releaseSshTunnel();
  }

  Future<void> forceClose() => disconnect();

  Future<String> info() async {
    if (!isConnected || _command == null) {
      throw StateError('Not connected to Redis');
    }
    final result = await _command!.send_object(['INFO']);
    return RedisBulkValue.fromReply(result).text ?? '';
  }

  /// Connects and disconnects. [error] is the reason in the user's terms
  /// (#1308).
  Future<({bool ok, String? error})> testConnection() async {
    try {
      await connect();
      return (ok: true, error: null);
    } catch (e) {
      debugPrint('RedisConnection.testConnection: $e');
      return (
        ok: false,
        error: describeDatabaseError(e, driver: DatabaseDriver.redis),
      );
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
    } catch (e) {
      logIgnored('redis_connection', e);
    }
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
    try {
      return await _command!.send_object(args);
    } catch (e) {
      final mapped = mapDatabaseError(e, driver: DatabaseDriver.redis);
      if (mapped is ConnectionLostException ||
          mapped is HostUnreachableException ||
          e is SocketException) {
        _isConnected = false;
        unawaited(disconnect());
      }
      rethrow;
    }
  }

  /// A command with typed arguments, its reply parsed once (#1571).
  ///
  /// Each argument is a `String`, `int`, `double`, `Uint8List` or
  /// [RedisBulkValue] (a key or value that may not be UTF-8); anything else is
  /// an [ArgumentError] here and not a malformed command on the wire.
  Future<RedisReply> command(List<Object> args) async =>
      RedisReply.from(await sendCommand([for (final a in args) _commandArg(a)]));

  static Object _commandArg(Object a) => switch (a) {
        RedisBulkValue() => a.commandArg,
        Uint8List() => redis.RedisBulk(a),
        String() || int() || double() || redis.RedisBulk() => a,
        _ => throw ArgumentError.value(
            a, 'args', 'not a Redis command argument (${a.runtimeType})'),
      };

  /// SELECT database index; later reconnects come back to it too.
  Future<void> selectDatabase(int db) async {
    await command(['SELECT', db]);
    database = db;
  }

  /// DBSIZE — number of keys in the currently selected database.
  Future<int> dbSize() async {
    return (await command(['DBSIZE'])).asInt();
  }

  /// CONFIG GET databases — max number of databases.
  Future<int> getMaxDatabases() async {
    try {
      final reply = (await command(['CONFIG', 'GET', 'databases'])).asArray();
      if (reply.length >= 2) return reply[1].asInt();
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
    final args = <Object>['SCAN', cursor];
    if (match != null && match.isNotEmpty) {
      args.addAll(['MATCH', match]);
    }
    args.addAll(['COUNT', count]);
    return _cursorAndBulks(await command(args));
  }

  /// The cursor and the bulk strings of a SCAN / SSCAN reply.
  static (int, List<RedisBulkValue>) _cursorAndBulks(RedisReply reply) {
    final parts = reply.asArray();
    if (parts.length != 2) {
      throw RedisProtocolException(
          'a scan reply has 2 parts, got ${parts.length}');
    }
    return (
      parts[0].asInt(),
      [for (final e in parts[1].asArray()) e.asBulk()],
    );
  }

  /// Field / value pairs of an HGETALL or HSCAN array.
  static Map<RedisBulkValue, RedisBulkValue> _pairs(List<RedisReply> items) => {
        for (var i = 0; i + 1 < items.length; i += 2)
          items[i].asBulk(): items[i + 1].asBulk(),
      };

  /// TYPE key.
  Future<String> keyType(Object key) async {
    final reply = await command(['TYPE', key]);
    return reply.asText() ?? 'none';
  }

  /// TTL key (returns -1 if no expiry, -2 if missing).
  Future<int> ttl(Object key) async {
    return (await command(['TTL', key])).asInt();
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
          command(['TYPE', key]).then(
            (v) => v.asText() ?? 'none',
            onError: (_) => 'unknown',
          ),
      ];
      final ttlFutures = <Future<int>>[
        for (final key in keys)
          command(['TTL', key]).then(
            (v) => v.asInt(),
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
    return (await command(['GET', key])).asBulkOrNull();
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
    return _pairs((await command(['HGETALL', key])).asArray());
  }

  /// HSCAN key cursor [COUNT count]. Returns (nextCursor, fields).
  Future<(int, Map<RedisBulkValue, RedisBulkValue>)> hscan(
    Object key, {
    int cursor = 0,
    int count = redisCollectionPageSize,
  }) async {
    final parts =
        (await command(['HSCAN', key, cursor, 'COUNT', count])).asArray();
    if (parts.length != 2) {
      throw RedisProtocolException(
          'a scan reply has 2 parts, got ${parts.length}');
    }
    return (parts[0].asInt(), _pairs(parts[1].asArray()));
  }

  /// HLEN key.
  Future<int> hlen(Object key) async {
    return (await command(['HLEN', key])).asInt();
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
    final reply = await command(['LRANGE', key, start, stop]);
    return [for (final e in reply.asArray()) e.asBulk()];
  }

  /// LLEN key.
  Future<int> llen(Object key) async {
    return (await command(['LLEN', key])).asInt();
  }

  /// RPUSH key value.
  Future<void> rpush(Object key, String value) async {
    _assertWritable();
    await sendCommand(['RPUSH', redisCommandArg(key), value]);
  }

  /// LINDEX key index.
  Future<RedisBulkValue?> lindex(Object key, int index) async {
    return (await command(['LINDEX', key, index])).asBulkOrNull();
  }

  /// LSET key index value.
  Future<void> lset(Object key, int index, String value) async {
    _assertWritable();
    await sendCommand(['LSET', redisCommandArg(key), index, value]);
  }

  /// LREM key count element.
  Future<int> lrem(Object key, int count, Object element) async {
    _assertWritable();
    return (await command(['LREM', key, count, element])).asInt();
  }

  /// SMEMBERS key.
  Future<List<RedisBulkValue>> smembers(Object key) async {
    final reply = await command(['SMEMBERS', key]);
    return [for (final e in reply.asArray()) e.asBulk()];
  }

  /// SSCAN key cursor [COUNT count]. Returns (nextCursor, members).
  Future<(int, List<RedisBulkValue>)> sscan(
    Object key, {
    int cursor = 0,
    int count = redisCollectionPageSize,
  }) async {
    return _cursorAndBulks(
        await command(['SSCAN', key, cursor, 'COUNT', count]));
  }

  /// SCARD key.
  Future<int> scard(Object key) async {
    return (await command(['SCARD', key])).asInt();
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
    final items =
        (await command(['ZRANGE', key, start, stop, 'WITHSCORES'])).asArray();
    return [
      for (var i = 0; i + 1 < items.length; i += 2)
        (items[i].asBulk(), items[i + 1].asDouble()),
    ];
  }

  /// ZCARD key.
  Future<int> zcard(Object key) async {
    return (await command(['ZCARD', key])).asInt();
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
    return (await command(['DEL', key])).asInt();
  }

  /// False once the server answered `UNLINK` with an unknown command (< 4.0).
  bool? _unlinkSupported;

  /// Removes [keys] in chunks of 200 and returns how many were removed.
  ///
  /// `UNLINK` frees the values in the background where `DEL` blocks the
  /// server on a large one; a server without it gets `DEL`. After the first
  /// chunk the rest are pipelined. When a chunk fails the error is rethrown
  /// once every chunk has answered, so some keys may be gone: reload (#1569).
  Future<int> delMany(Iterable<Object> keys) async {
    _assertWritable();
    final list = keys.toList();
    if (list.isEmpty) return 0;
    const chunkSize = 200;
    final chunks = [
      for (var i = 0; i < list.length; i += chunkSize)
        [
          for (final key in list.sublist(i, min(i + chunkSize, list.length)))
            key,
        ],
    ];

    // The first chunk on its own tells whether the server knows UNLINK.
    var total = 0;
    var verb = _unlinkSupported == false ? 'DEL' : 'UNLINK';
    try {
      total += (await command([verb, ...chunks.first])).asInt();
    } catch (e) {
      if (verb != 'UNLINK' || !_isUnknownCommand(e)) rethrow;
      verb = 'DEL';
      total += (await command([verb, ...chunks.first])).asInt();
    }
    _unlinkSupported ??= verb == 'UNLINK';
    if (chunks.length == 1) return total;

    Object? firstError;
    StackTrace? firstStack;
    final cmd = _command;
    cmd?.pipe_start();
    try {
      final replies = await Future.wait([
        for (final chunk in chunks.skip(1))
          command([verb, ...chunk]).then<int>(
            (reply) => reply.asInt(),
            onError: (Object e, StackTrace st) {
              firstError ??= e;
              firstStack ??= st;
              return 0;
            },
          ),
      ]);
      for (final removed in replies) {
        total += removed;
      }
    } finally {
      cmd?.pipe_end();
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
    return total;
  }

  static bool _isUnknownCommand(Object error) =>
      error.toString().toLowerCase().contains('unknown command');

  /// RENAME old new.
  Future<void> rename(Object oldKey, String newKey) async {
    _assertWritable();
    await sendCommand(['RENAME', redisCommandArg(oldKey), newKey]);
  }

  /// RENAMENX old new. Returns 1 if key was renamed, 0 if newKey already exists.
  Future<int> renamenx(Object oldKey, String newKey) async {
    _assertWritable();
    return (await command(['RENAMENX', oldKey, newKey])).asInt();
  }

  /// EXISTS key. Returns 1 if key exists, 0 if missing.
  Future<int> exists(Object key) async {
    return (await command(['EXISTS', key])).asInt();
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
