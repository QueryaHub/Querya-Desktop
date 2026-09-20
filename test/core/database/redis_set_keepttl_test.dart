import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';

class _SetCommandFake extends RedisConnectionTestFake {
  final List<List<dynamic>> commands = [];
  bool rejectKeepTtl = false;
  int ttlResult = 300;
  Object? setResult = 'OK';

  @override
  Future<dynamic> sendCommand(List<dynamic> args) async {
    commands.add(List<dynamic>.from(args));
    final op = args.first.toString().toUpperCase();
    if (op == 'SET') {
      if (rejectKeepTtl &&
          args.any((a) => a.toString().toUpperCase() == 'KEEPTTL')) {
        throw RedisConnectionException('ERR syntax error');
      }
      return setResult;
    }
    if (op == 'TTL') return ttlResult;
    return super.sendCommand(args);
  }
}

void main() {
  group('RedisConnection.set KEEPTTL', () {
    test('Save without EX uses SET KEEPTTL XX', () async {
      final fake = _SetCommandFake();
      await fake.connect();

      await fake.set('session:1', 'new-value');

      expect(fake.commands, [
        ['SET', 'session:1', 'new-value', 'KEEPTTL', 'XX'],
      ]);
    });

    test('does not recreate a key that already expired (XX miss)', () async {
      final fake = _SetCommandFake()..setResult = null;
      await fake.connect();

      await expectLater(
        fake.set('session:1', 'new-value'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Key no longer exists',
          ),
        ),
      );
      expect(fake.commands, [
        ['SET', 'session:1', 'new-value', 'KEEPTTL', 'XX'],
      ]);
    });

    test('Redis < 6: TTL then SET EX when KEEPTTL is rejected', () async {
      final fake = _SetCommandFake()
        ..rejectKeepTtl = true
        ..ttlResult = 300;
      await fake.connect();

      await fake.set('session:1', 'new-value');

      expect(fake.commands, [
        ['SET', 'session:1', 'new-value', 'KEEPTTL', 'XX'],
        ['TTL', 'session:1'],
        ['SET', 'session:1', 'new-value', 'EX', 300],
      ]);
    });

    test('Redis < 6: does not SET when TTL is -2', () async {
      final fake = _SetCommandFake()
        ..rejectKeepTtl = true
        ..ttlResult = -2;
      await fake.connect();

      await expectLater(
        fake.set('session:1', 'new-value'),
        throwsA(isA<StateError>()),
      );
      expect(fake.commands, [
        ['SET', 'session:1', 'new-value', 'KEEPTTL', 'XX'],
        ['TTL', 'session:1'],
      ]);
    });

    test('Redis < 6: plain SET when key has no expiry (TTL -1)', () async {
      final fake = _SetCommandFake()
        ..rejectKeepTtl = true
        ..ttlResult = -1;
      await fake.connect();

      await fake.set('session:1', 'new-value');

      expect(fake.commands.last, ['SET', 'session:1', 'new-value']);
    });

    test('explicit ttlSeconds still sends SET EX', () async {
      final fake = _SetCommandFake();
      await fake.connect();

      await fake.set('session:1', 'new-value', ttlSeconds: 10);

      expect(fake.commands, [
        ['SET', 'session:1', 'new-value', 'EX', 10],
      ]);
    });

    test('keepTtl: false sends a plain SET', () async {
      final fake = _SetCommandFake();
      await fake.connect();

      await fake.set('session:1', 'new-value', keepTtl: false);

      expect(fake.commands, [
        ['SET', 'session:1', 'new-value'],
      ]);
    });
  });
}
