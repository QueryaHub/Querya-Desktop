import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/features/connections/connection_test_result.dart';

/// #1308: Test Connection says why it failed.
void main() {
  group('connectionTestMessage', () {
    test('success, a bare failure, an exception and a reason', () {
      expect(connectionTestMessage('success'), 'Connection successful!');
      expect(connectionTestMessage('failed'), 'Connection failed');
      expect(connectionTestMessage('error: boom'), 'boom');
      // The SQLite form writes `error:` without a space; no letter is lost.
      expect(connectionTestMessage('error:no such file'), 'no such file');
      expect(
        connectionTestMessage(
            'Authentication failed. Check the username and password'),
        'Authentication failed. Check the username and password',
      );
    });

    test('a reason stays on screen longer than a success', () {
      expect(connectionTestResultLifetime('success'),
          lessThan(connectionTestResultLifetime('Authentication failed')));
    });
  });

  /// A port nobody listens on.
  Future<int> closedPort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }

  group('testConnection returns the reason', () {
    test('Redis: a wrong password is an authentication failure', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((socket) {
        socket.listen((data) {
          final text = utf8.decode(data, allowMalformed: true).toUpperCase();
          if (text.contains('AUTH')) {
            socket.write('-WRONGPASS invalid username-password pair\r\n');
          } else if (text.contains('PING')) {
            socket.write('+PONG\r\n');
          }
        }, onError: (_) {}, onDone: socket.destroy);
      });

      final r = await RedisConnection(
        id: 0,
        name: 'r',
        host: '127.0.0.1',
        port: server.port,
        password: 'wrong',
      ).testConnection();

      expect(r.ok, isFalse);
      expect(r.error, contains('Authentication failed'));
    });

    test('Redis: nothing listening is unreachable', () async {
      final r = await RedisConnection(
        id: 0,
        name: 'r',
        host: '127.0.0.1',
        port: await closedPort(),
      ).testConnection();

      expect(r.ok, isFalse);
      expect(r.error, contains('Cannot reach'));
    });

    test('MySQL: nothing listening is unreachable', () async {
      final r = await MysqlConnection(
        id: 0,
        name: 'm',
        host: '127.0.0.1',
        port: await closedPort(),
        useSSL: false,
      ).testConnection();

      expect(r.ok, isFalse);
      expect(r.error, contains('Cannot reach'));
    });
  });
}
