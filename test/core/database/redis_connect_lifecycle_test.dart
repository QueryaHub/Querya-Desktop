import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/querya_database_exception.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';

/// #1307: connect timeout, no socket left after a failed AUTH, single-flight.
///
/// A tiny RESP server: `AUTH <password>` is checked against [password], `PING`
/// is answered, and a [silent] server accepts the connection and says nothing.
class _FakeRedis {
  _FakeRedis._(this._server, {this.password, this.silent = false}) {
    _server.listen(_onClient);
  }

  static Future<_FakeRedis> start({String? password, bool silent = false}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeRedis._(server, password: password, silent: silent);
  }

  final ServerSocket _server;
  final String? password;
  final bool silent;

  int accepted = 0;
  int closedByClient = 0;
  final _sockets = <Socket>[];

  int get port => _server.port;

  void _onClient(Socket socket) {
    accepted++;
    _sockets.add(socket);
    socket.listen(
      (data) {
        if (silent) return;
        final text = utf8.decode(data, allowMalformed: true);
        final upper = text.toUpperCase();
        if (upper.contains('AUTH')) {
          final ok = password != null && text.contains(password!);
          if (ok) _authed.add(socket);
          socket.write(ok
              ? '+OK\r\n'
              : '-WRONGPASS invalid username-password pair or user is '
                  'disabled.\r\n');
        } else if (upper.contains('PING')) {
          if (password != null && _needsAuth(socket)) {
            socket.write('-NOAUTH Authentication required.\r\n');
          } else {
            socket.write('+PONG\r\n');
          }
        }
      },
      onDone: () {
        closedByClient++;
        socket.destroy();
      },
      onError: (_) {},
    );
  }

  final _authed = <Socket>{};
  bool _needsAuth(Socket s) => !_authed.contains(s);

  Future<void> close() async {
    for (final s in _sockets) {
      s.destroy();
    }
    await _server.close();
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late _FakeRedis server;

  tearDown(() async => server.close());

  RedisConnection client({
    String? password,
    Duration connectTimeout = const Duration(seconds: 2),
  }) =>
      RedisConnection(
        id: 0,
        name: 'fake',
        host: '127.0.0.1',
        port: server.port,
        password: password,
        connectTimeout: connectTimeout,
      );

  test('a wrong password fails and the socket is closed', () async {
    server = await _FakeRedis.start(password: 'right');
    final c = client(password: 'wrong');

    await expectLater(c.connect(), throwsA(isA<AuthFailedException>()));

    expect(c.isConnected, isFalse);
    await _until(() => server.closedByClient > 0);
    expect(server.accepted, 1);
    expect(server.closedByClient, 1);
  });

  test('a server that never answers fails after the timeout and is closed',
      () async {
    server = await _FakeRedis.start(silent: true);
    final c = client(connectTimeout: const Duration(milliseconds: 300));

    final started = DateTime.now();
    await expectLater(
        c.connect(), throwsA(isA<ConnectionTimeoutException>()));

    expect(DateTime.now().difference(started).inSeconds, lessThan(5));
    await _until(() => server.closedByClient > 0);
    expect(server.closedByClient, 1);
  });

  test('two concurrent connects open one connection', () async {
    server = await _FakeRedis.start();
    final c = client();

    await Future.wait([c.connect(), c.connect()]);

    expect(c.isConnected, isTrue);
    expect(server.accepted, 1);
    await c.disconnect();
  });

  test('a failed attempt can be retried', () async {
    server = await _FakeRedis.start(silent: true);
    final c = client(connectTimeout: const Duration(milliseconds: 200));
    await expectLater(c.connect(), throwsA(isA<ConnectionTimeoutException>()));
    await expectLater(c.connect(), throwsA(isA<ConnectionTimeoutException>()));
    expect(server.accepted, 2);
  });
}
