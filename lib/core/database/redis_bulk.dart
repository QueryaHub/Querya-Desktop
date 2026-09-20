import 'dart:convert';
import 'dart:typed_data';

import 'package:redis/redis.dart' as redis;

/// Bulk string from Redis: UTF-8 text when valid, otherwise raw bytes.
class RedisBulkValue {
  RedisBulkValue._({required this.bytes, required this.text});

  factory RedisBulkValue.utf8(String value) {
    return RedisBulkValue._(
      bytes: Uint8List.fromList(utf8.encode(value)),
      text: value,
    );
  }

  factory RedisBulkValue.fromReply(Object? reply) {
    if (reply == null) {
      return RedisBulkValue._(bytes: Uint8List(0), text: '');
    }
    if (reply is String) {
      return RedisBulkValue.utf8(reply);
    }
    if (reply is int) {
      return RedisBulkValue.utf8(reply.toString());
    }
    if (reply is double) {
      return RedisBulkValue.utf8(reply.toString());
    }
    final bytes = _asBytes(reply);
    if (bytes != null) {
      return RedisBulkValue._(bytes: bytes, text: _tryUtf8(bytes));
    }
    return RedisBulkValue.utf8(reply.toString());
  }

  final Uint8List bytes;

  /// Null when [bytes] are not valid UTF-8.
  final String? text;

  bool get isUtf8 => text != null;

  bool get isEmpty => bytes.isEmpty;

  /// Argument for `send_object`: a Dart [String] when UTF-8, else [redis.RedisBulk].
  Object get commandArg => isUtf8 ? text! : redis.RedisBulk(bytes);

  /// UI label: the UTF-8 string, or a hex preview that is not `List.toString()`.
  String get label {
    if (text != null) return text!;
    if (bytes.isEmpty) return '(empty)';
    final hex = toHex();
    if (hex.length <= 48) return '0x$hex';
    return '0x${hex.substring(0, 48)}… (${bytes.length} B)';
  }

  String toHex() {
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  String toBase64() => base64Encode(bytes);

  @override
  bool operator ==(Object other) {
    if (other is! RedisBulkValue || other.bytes.length != bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => label;
}

int redisReplyInt(Object? reply, [int fallback = 0]) {
  if (reply is int) return reply;
  final text = RedisBulkValue.fromReply(reply).text;
  return int.tryParse(text ?? '') ?? fallback;
}

double redisReplyDouble(Object? reply, [double fallback = 0]) {
  if (reply is num) return reply.toDouble();
  final text = RedisBulkValue.fromReply(reply).text;
  return double.tryParse(text ?? '') ?? fallback;
}

Object redisCommandArg(Object value) {
  if (value is RedisBulkValue) return value.commandArg;
  return value;
}

Uint8List? _asBytes(Object reply) {
  if (reply is Uint8List) return reply;
  if (reply is List<int>) return Uint8List.fromList(reply);
  if (reply is List && reply.isNotEmpty && reply.every((e) => e is int)) {
    return Uint8List.fromList(List<int>.from(reply));
  }
  if (reply is List && reply.isEmpty) return Uint8List(0);
  return null;
}

String? _tryUtf8(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}
