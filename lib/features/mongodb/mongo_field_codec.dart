import 'dart:convert';

import 'package:mongo_dart/mongo_dart.dart';
import 'package:querya_desktop/features/mongodb/mongo_ejson.dart';

/// Mongo forbids `$set` of `_id` on an existing document.
bool mongoFieldIsReadOnly(String field) => field == '_id';

/// True when `$set` would treat [field] as a nested path (`a.b`), not as a
/// literal top-level key. `$set` has no escape for dots, so such a field cannot
/// be updated on its own without rewriting a different subtree.
bool mongoFieldNameIsDottedPath(String field) => field.contains('.');

/// Throws if [field] cannot be updated with `$set` on an existing document.
void mongoAssertFieldEditable(String field) {
  if (mongoFieldIsReadOnly(field)) {
    throw StateError(
      'MongoDB forbids \$set of _id on an existing document',
    );
  }
  if (mongoFieldNameIsDottedPath(field)) {
    throw StateError(
      'Field "$field" contains a dot, so a single-field update would be '
      'treated as a nested path and change a different value. '
      'Edit the whole document in the JSON editor instead.',
    );
  }
}

/// Display string for a MongoDB document field in the Cell Inspector.
String mongoFieldToDisplay(Object? value) {
  if (value == null) return 'NULL';
  if (value is String) return value;
  if (value is bool || value is num) return value.toString();
  if (value is ObjectId) return value.oid;
  if (value is DateTime) return value.toUtc().toIso8601String();
  try {
    final ejson = EJsonCodec.deserialize(
      BsonCodec.serialize(<String, dynamic>{'v': value}),
      relaxed: true,
    )['v'];
    if (ejson is Map || ejson is List) {
      return const JsonEncoder.withIndent('  ').convert(ejson);
    }
    return ejson?.toString() ?? value.toString();
  } catch (_) {
    return value.toString();
  }
}

/// Parses an inspector string back into a BSON value of [original]'s type.
///
/// Strings stay strings even when they look like numbers. ObjectId, DateTime,
/// Timestamp, Decimal128, Int32/Int64, and Double keep their width.
Object? mongoDisplayToValue(String text, {Object? original}) {
  if (text == 'NULL') return null;

  if (original is String) return text;

  final trimmed = text.trim();

  if (original is bool) {
    if (trimmed == 'true') return true;
    if (trimmed == 'false') return false;
    throw FormatException('Expected true or false, got "$trimmed"');
  }
  if (original is int) return int.parse(trimmed);
  if (original is double) return double.parse(trimmed);
  if (original is ObjectId) return _parseObjectId(trimmed);
  if (original is DateTime) return _parseDateTime(trimmed);
  if (original is Timestamp) return _parseTimestamp(trimmed);
  if (original is Map || original is List) {
    return _parseWrappedEjson(trimmed);
  }
  if (original != null) {
    return _parseKeepingRuntimeType(trimmed, original);
  }

  if (trimmed.isEmpty) return '';
  if (trimmed == 'true') return true;
  if (trimmed == 'false') return false;
  if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
      (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
    try {
      return _parseWrappedEjson(trimmed);
    } catch (_) {
      return text;
    }
  }
  return text;
}

ObjectId _parseObjectId(String trimmed) {
  if (ObjectId.isValidHexId(trimmed)) {
    return ObjectId.fromHexString(trimmed);
  }
  final fromLiteral = _objectIdFromShellLiteral(trimmed);
  if (fromLiteral != null) return fromLiteral;
  if (trimmed.startsWith('{')) {
    final decoded = json.decode(trimmed);
    if (decoded is Map && decoded[r'$oid'] is String) {
      return ObjectId.fromHexString(decoded[r'$oid'] as String);
    }
  }
  throw FormatException('Not a valid ObjectId: $trimmed');
}

ObjectId? _objectIdFromShellLiteral(String trimmed) {
  const prefix = 'ObjectId(';
  if (!trimmed.startsWith(prefix) || !trimmed.endsWith(')')) return null;
  final inner = trimmed.substring(prefix.length, trimmed.length - 1).trim();
  if (inner.length < 2) return null;
  final quote = inner[0];
  if (quote != '"' && quote != "'") return null;
  if (!inner.endsWith(quote)) return null;
  final hex = inner.substring(1, inner.length - 1);
  if (!ObjectId.isValidHexId(hex)) return null;
  return ObjectId.fromHexString(hex);
}

DateTime _parseDateTime(String trimmed) {
  if (trimmed.startsWith('{')) {
    final value = _parseWrappedEjson(trimmed);
    if (value is DateTime) return value;
  }
  return DateTime.parse(trimmed).toUtc();
}

Timestamp _parseTimestamp(String trimmed) {
  if (trimmed.startsWith('{')) {
    final value = _parseWrappedEjson(trimmed);
    if (value is Timestamp) return value;
  }
  throw FormatException('Not a valid Timestamp: $trimmed');
}

Object? _parseWrappedEjson(String trimmed) {
  return mongoDocumentFromEjson('{"v": $trimmed}')['v'];
}

Object? _parseKeepingRuntimeType(String trimmed, Object original) {
  final typeName = original.runtimeType.toString();
  final candidates = <String>[
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) '{"v": $trimmed}',
    '{"v": {"\$numberLong": ${json.encode(trimmed)}}}',
    '{"v": {"\$numberDecimal": ${json.encode(trimmed)}}}',
    '{"v": {"\$numberInt": ${json.encode(trimmed)}}}',
    '{"v": {"\$numberDouble": ${json.encode(trimmed)}}}',
  ];
  if (typeName == 'Int64') {
    candidates.insert(0, '{"v": {"\$numberLong": ${json.encode(trimmed)}}}');
  }
  if (typeName == 'Decimal') {
    candidates.insert(0, '{"v": {"\$numberDecimal": ${json.encode(trimmed)}}}');
  }
  for (final wrapped in candidates) {
    try {
      final v = mongoDocumentFromEjson(wrapped)['v'];
      if (v.runtimeType == original.runtimeType) return v;
    } catch (_) {}
  }
  throw FormatException(
    'Could not parse "$trimmed" as $typeName',
  );
}
