import 'dart:typed_data';

import 'redis_bulk.dart';

/// The reply to a Redis command was not the shape the caller needs.
class RedisProtocolException implements Exception {
  const RedisProtocolException(this.message);

  final String message;

  @override
  String toString() => 'RedisProtocolException: $message';
}

/// A Redis reply, parsed once where it leaves the socket so that no caller
/// has to test `is List` / `is int` on a `dynamic` (#1571).
///
/// The `redis` package gives integers as `int`, simple strings as `String`,
/// bulk strings as bytes (Querya parses with `RedisParserBulkBinary`), arrays
/// as `List` and nil as `null`. An error reply is thrown by the package and
/// never arrives here as a value; [RedisErrorReply] is for a caller that wants
/// to show one it caught.
sealed class RedisReply {
  const RedisReply();

  factory RedisReply.from(Object? raw) {
    if (raw == null) return const RedisNil();
    if (raw is int) return RedisInt(raw);
    if (raw is double) return RedisBulk(RedisBulkValue.fromReply(raw));
    if (raw is String) return RedisSimple(raw);
    if (raw is Uint8List || raw is List<int>) {
      return RedisBulk(RedisBulkValue.fromReply(raw));
    }
    if (raw is List) {
      // Bulk bytes from a source that does not type them: all ints, or empty.
      if (raw.isNotEmpty && raw.every((e) => e is int)) {
        return RedisBulk(RedisBulkValue.fromReply(raw));
      }
      return RedisArray([for (final e in raw) RedisReply.from(e)]);
    }
    return RedisBulk(RedisBulkValue.fromReply(raw));
  }

  bool get isNil => this is RedisNil;

  /// The integer: an integer reply, or a string/bulk that holds one.
  int asInt();

  /// The elements of an array reply.
  List<RedisReply> asArray();

  /// The value as a bulk string; a nil is an empty one.
  RedisBulkValue asBulk();

  /// The UTF-8 text, or null when the bytes are not UTF-8.
  String? asText() => asBulk().text;

  /// A double from a string/bulk or an integer reply.
  double asDouble();

  /// The bulk value, or null for a nil reply (`GET` of a missing key).
  RedisBulkValue? asBulkOrNull() => isNil ? null : asBulk();

  Never _mismatch(String wanted) =>
      throw RedisProtocolException('expected $wanted, got $runtimeType');
}

/// `$-1` / `*-1`: no value.
final class RedisNil extends RedisReply {
  const RedisNil();

  @override
  int asInt() => _mismatch('an integer');
  @override
  List<RedisReply> asArray() => _mismatch('an array');
  @override
  RedisBulkValue asBulk() => RedisBulkValue.fromReply(null);
  @override
  double asDouble() => _mismatch('a number');
}

final class RedisInt extends RedisReply {
  const RedisInt(this.value);

  final int value;

  @override
  int asInt() => value;
  @override
  List<RedisReply> asArray() => _mismatch('an array');
  @override
  RedisBulkValue asBulk() => RedisBulkValue.fromReply(value);
  @override
  double asDouble() => value.toDouble();
}

/// `+OK` style status, or a string a source gave as text.
final class RedisSimple extends RedisReply {
  const RedisSimple(this.text);

  final String text;

  @override
  int asInt() => int.tryParse(text) ?? _mismatch('an integer');
  @override
  List<RedisReply> asArray() => _mismatch('an array');
  @override
  RedisBulkValue asBulk() => RedisBulkValue.utf8(text);
  @override
  double asDouble() => double.tryParse(text) ?? _mismatch('a number');
}

final class RedisBulk extends RedisReply {
  const RedisBulk(this.value);

  final RedisBulkValue value;

  @override
  int asInt() => int.tryParse(value.text ?? '') ?? _mismatch('an integer');
  @override
  List<RedisReply> asArray() => _mismatch('an array');
  @override
  RedisBulkValue asBulk() => value;
  @override
  double asDouble() => double.tryParse(value.text ?? '') ?? _mismatch('a number');
}

final class RedisArray extends RedisReply {
  const RedisArray(this.items);

  final List<RedisReply> items;

  @override
  int asInt() => _mismatch('an integer');
  @override
  List<RedisReply> asArray() => items;
  @override
  RedisBulkValue asBulk() => _mismatch('a bulk string');
  @override
  double asDouble() => _mismatch('a number');
}

/// An error reply (`-ERR ...`) held as a value.
final class RedisErrorReply extends RedisReply {
  const RedisErrorReply(this.message);

  final String message;

  @override
  int asInt() => _mismatch('an integer');
  @override
  List<RedisReply> asArray() => _mismatch('an array');
  @override
  RedisBulkValue asBulk() => _mismatch('a bulk string');
  @override
  double asDouble() => _mismatch('a number');
}
