import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/core/database/redis_reply.dart';

import '../../support/redis_connection_test_fake.dart';

void main() {
  group('RedisReply.from', () {
    test('sorts what the redis package returns into the sealed types', () {
      expect(RedisReply.from(null), isA<RedisNil>());
      expect(RedisReply.from(7), isA<RedisInt>());
      expect(RedisReply.from('OK'), isA<RedisSimple>());
      expect(RedisReply.from(Uint8List.fromList([104, 105])), isA<RedisBulk>());
      expect(RedisReply.from(<int>[104, 105]), isA<RedisBulk>());
      expect(RedisReply.from(<Object?>['a', 1, null]), isA<RedisArray>());
    });

    test('an array holds replies, nested arrays included', () {
      final a = RedisReply.from(<Object?>[
        '5',
        <Object?>['x', 'y'],
      ]).asArray();
      expect(a[0].asInt(), 5);
      expect(a[1].asArray().map((e) => e.asText()), ['x', 'y']);
    });
  });

  group('accessors', () {
    test('asInt reads an integer reply and a string that holds one', () {
      expect(RedisReply.from(42).asInt(), 42);
      expect(RedisReply.from('42').asInt(), 42);
      expect(RedisReply.from(Uint8List.fromList([52, 50])).asInt(), 42);
      expect(RedisReply.from(-2).asInt(), -2);
    });

    test('a wrong shape is a RedisProtocolException, not a fallback', () {
      expect(() => RedisReply.from('abc').asInt(),
          throwsA(isA<RedisProtocolException>()));
      expect(() => RedisReply.from(null).asInt(),
          throwsA(isA<RedisProtocolException>()));
      expect(() => RedisReply.from(<Object?>['a']).asInt(),
          throwsA(isA<RedisProtocolException>()));
      expect(() => RedisReply.from(5).asArray(),
          throwsA(isA<RedisProtocolException>()));
      expect(() => RedisReply.from(<Object?>['a']).asBulk(),
          throwsA(isA<RedisProtocolException>()));
    });

    test('nil is no value for GET and an empty bulk elsewhere', () {
      expect(RedisReply.from(null).asBulkOrNull(), isNull);
      expect(RedisReply.from('v').asBulkOrNull()?.text, 'v');
      expect(RedisReply.from(null).asBulk().isEmpty, isTrue);
    });

    test('bytes that are not UTF-8 keep their bytes and have no text', () {
      final r = RedisReply.from(Uint8List.fromList([0xff, 0xfe]));
      expect(r.asText(), isNull);
      expect(r.asBulk().bytes, [0xff, 0xfe]);
    });

    test('asDouble reads scores', () {
      expect(RedisReply.from('1.5').asDouble(), 1.5);
      expect(RedisReply.from(2).asDouble(), 2.0);
      expect(() => RedisReply.from('x').asDouble(),
          throwsA(isA<RedisProtocolException>()));
    });
  });

  group('RedisConnection.command', () {
    test('arguments are converted in one place', () async {
      final fake = RedisConnectionTestFake();
      await fake.connect();
      await fake.command(['SELECT', 0]);
      await fake.command(['TYPE', RedisBulkValue.utf8('k')]);
      await fake.command(['TYPE', Uint8List.fromList([1, 2])]);
      expect(fake.sentCommands, containsAll(['SELECT', 'TYPE']));
    });

    test('an argument that is not a command argument is refused', () async {
      final fake = RedisConnectionTestFake();
      await fake.connect();
      expect(() => fake.command(['GET', true]), throwsArgumentError);
      expect(() => fake.command(['GET', <String>['a']]), throwsArgumentError);
    });
  });
}
