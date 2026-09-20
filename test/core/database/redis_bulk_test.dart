import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:redis/redis.dart' as redis;

void main() {
  test('UTF-8 string reply stays text, not List.toString', () {
    final v = RedisBulkValue.fromReply('hello');
    expect(v.isUtf8, isTrue);
    expect(v.text, 'hello');
    expect(v.label, 'hello');
    expect(v.commandArg, 'hello');
  });

  test('UTF-8 bulk bytes decode to text', () {
    final v = RedisBulkValue.fromReply(utf8.encode('café'));
    expect(v.isUtf8, isTrue);
    expect(v.text, 'café');
    expect(v.label, 'café');
  });

  test('non-UTF-8 bulk is hex/base64, not replacement characters', () {
    final raw = Uint8List.fromList(const [0xff, 0xfe, 0x01, 0x1f, 0x8b]);
    final v = RedisBulkValue.fromReply(raw);
    expect(v.isUtf8, isFalse);
    expect(v.text, isNull);
    expect(v.label, '0xfffe011f8b');
    expect(v.toHex(), 'fffe011f8b');
    expect(v.toBase64(), base64Encode(raw));
    expect(v.label.contains('['), isFalse);
    expect(v.commandArg, isA<redis.RedisBulk>());
  });

  test('SCAN cursor bulk digits parse as int, not List.toString', () {
    expect(redisReplyInt(utf8.encode('42')), 42);
    expect(redisReplyInt(42), 42);
    expect(redisReplyInt('7'), 7);
  });
}
