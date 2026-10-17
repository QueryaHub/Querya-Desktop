import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/redis_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// A RESP server that answers `PING` and `SELECT` and records every command.
class _RecordingRedis {
  _RecordingRedis._(this._server) {
    _server.listen(_onClient);
  }

  static Future<_RecordingRedis> start() async => _RecordingRedis._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  final commands = <List<String>>[];
  final _sockets = <Socket>[];

  int get port => _server.port;

  void _onClient(Socket socket) {
    _sockets.add(socket);
    var buffer = '';
    socket.listen(
      (data) {
        buffer += utf8.decode(data, allowMalformed: true);
        while (true) {
          final parsed = _parseArray(buffer);
          if (parsed == null) break;
          buffer = buffer.substring(parsed.$2);
          final args = parsed.$1;
          commands.add(args);
          socket.write(args.first.toUpperCase() == 'PING' ? '+PONG\r\n' : '+OK\r\n');
        }
      },
      onDone: socket.destroy,
      onError: (_) {},
    );
  }

  /// `*<n>\r\n` then n `$<len>\r\n<arg>\r\n`; null until all of it is there.
  static (List<String>, int)? _parseArray(String s) {
    if (!s.startsWith('*')) return null;
    var at = s.indexOf('\r\n');
    if (at < 0) return null;
    final count = int.parse(s.substring(1, at));
    at += 2;
    final args = <String>[];
    for (var i = 0; i < count; i++) {
      final end = s.indexOf('\r\n', at);
      if (end < 0) return null;
      final len = int.parse(s.substring(at + 1, end));
      final start = end + 2;
      if (s.length < start + len + 2) return null;
      args.add(s.substring(start, start + len));
      at = start + len + 2;
    }
    return (args, at);
  }

  /// Drops every client, as a server restart or a network blip would.
  void dropClients() {
    for (final s in _sockets) {
      s.destroy();
    }
    _sockets.clear();
  }

  Future<void> close() async {
    dropClients();
    await _server.close();
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

ConnectionRow _row(int id) => ConnectionRow(
      id: id,
      type: 'redis',
      name: 'r',
      createdAt: '2026-01-01T00:00:00Z',
    );

void main() {
  group('one socket per database (#1569)', () {
    test('explorers of different databases do not share a socket', () {
      const id = 8150;
      final db0 = RedisService.instance.acquire(
        _row(id),
        role: RedisSessionRole.explorer,
      );
      final db3 = RedisService.instance.acquire(
        _row(id),
        role: RedisSessionRole.explorer,
        database: 3,
      );
      expect(db3, isNot(same(db0)));
      expect(db0.database, 0);
      expect(db3.database, 3);
      expect(
        RedisService.instance.acquire(
          _row(id),
          role: RedisSessionRole.explorer,
          database: 3,
        ),
        same(db3),
      );
    });

    test('the CLI has its own socket next to the explorer', () {
      const id = 8151;
      final explorer = RedisService.instance.acquire(
        _row(id),
        role: RedisSessionRole.explorer,
        database: 2,
      );
      final cli = RedisService.instance.acquire(
        _row(id),
        role: RedisSessionRole.cli,
        database: 2,
      );
      expect(cli, isNot(same(explorer)));
      expect(cli.database, 2);
    });

    test('disconnectByConnectionId drops every role and database', () async {
      const id = 8152;
      for (final db in [0, 1, 5]) {
        RedisService.instance.acquire(
          _row(id),
          role: RedisSessionRole.explorer,
          database: db,
        );
      }
      RedisService.instance.acquire(_row(id), role: RedisSessionRole.cli);
      await RedisService.instance.disconnectByConnectionId(id);
      for (final db in [0, 1, 5]) {
        expect(
          RedisService.instance.getConnection(
            id,
            role: RedisSessionRole.explorer,
            database: db,
          ),
          isNull,
        );
      }
      expect(
        RedisService.instance.getConnection(id, role: RedisSessionRole.cli),
        isNull,
      );
    });

    test('selectDatabase moves the socket it is sent on, nothing else',
        () async {
      final cli = RedisConnectionTestFake();
      final explorer = RedisConnectionTestFake();
      await cli.connect();
      await explorer.connect();

      await cli.selectDatabase(3);

      expect(cli.database, 3);
      expect(explorer.database, 0);
      expect(explorer.sentCommands, isNot(contains('SELECT')));
    });
  });

  group('SELECT on connect (#1569)', () {
    late _RecordingRedis server;

    setUp(() async => server = await _RecordingRedis.start());
    tearDown(() async => server.close());

    RedisConnection connection({required int database}) => RedisConnection(
          id: 0,
          name: 'r',
          host: '127.0.0.1',
          port: server.port,
        )..database = database;

    test('db 0 sends no SELECT', () async {
      final conn = connection(database: 0);
      await conn.connect();
      await conn.disconnect();
      expect(server.commands.map((c) => c.first.toUpperCase()),
          isNot(contains('SELECT')));
    });

    test('a socket for db 3 selects it after the handshake', () async {
      final conn = connection(database: 3);
      await conn.connect();
      await conn.disconnect();
      expect(server.commands, contains(equals(['SELECT', '3'])));
    });

    test('a reconnect comes back to the database, not db 0', () async {
      final conn = connection(database: 0);
      await conn.connect();
      await conn.selectDatabase(4);

      server.dropClients();
      await _until(() => !conn.isConnected);
      server.commands.clear();

      await conn.connect();
      await conn.disconnect();
      expect(server.commands, contains(equals(['SELECT', '4'])));
    });
  });

  group('delMany (#1569)', () {
    List<String> keys(int n) => [for (var i = 0; i < n; i++) 'k$i'];

    test('uses UNLINK in chunks of 200', () async {
      final fake = RedisConnectionTestFake();
      await fake.connect();
      await fake.delMany(keys(450));
      expect(fake.sentCommands, ['UNLINK', 'UNLINK', 'UNLINK']);
    });

    test('falls back to DEL on a server without UNLINK, and remembers',
        () async {
      final fake = RedisConnectionTestFake(unlinkUnsupported: true);
      await fake.connect();
      await fake.delMany(keys(450));
      expect(fake.sentCommands, ['UNLINK', 'DEL', 'DEL', 'DEL']);

      fake.sentCommands.clear();
      await fake.delMany(keys(10));
      expect(fake.sentCommands, ['DEL']);
    });

    test('returns how many keys were removed', () async {
      final fake = RedisConnectionTestFake(
        firstScanKeys: const ['a', 'b'],
        secondScanKeys: const ['c'],
      );
      await fake.connect();
      expect(await fake.delMany(['a', 'b', 'c', 'missing']), 3);
    });

    test('a failed chunk is reported after the others have run', () async {
      final fake = _FailingChunkFake(failOnCall: 2);
      await fake.connect();
      await expectLater(fake.delMany(keys(600)), throwsA(isA<StateError>()));
      expect(fake.calls, 3);
    });
  });
}

class _FailingChunkFake extends RedisConnectionTestFake {
  _FailingChunkFake({required this.failOnCall});

  final int failOnCall;
  int calls = 0;

  @override
  Future<dynamic> sendCommand(List<dynamic> args) async {
    final op = args.first.toString().toUpperCase();
    if (op == 'UNLINK') {
      calls++;
      if (calls == failOnCall) throw StateError('chunk $calls failed');
    }
    return super.sendCommand(args);
  }
}
