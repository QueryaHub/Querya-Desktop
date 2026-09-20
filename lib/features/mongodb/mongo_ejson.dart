import 'dart:convert';

import 'package:mongo_dart/mongo_dart.dart';

/// Pretty-print a MongoDB document as relaxed Extended JSON.
///
/// ObjectId, DateTime, NumberLong, NumberDecimal, BinData, and Timestamp
/// stay typed (`$oid`, `$date`, …) instead of falling back to `toString()`.
String mongoDocumentToEjson(Map<String, dynamic> doc) {
  final ejson = EJsonCodec.deserialize(
    BsonCodec.serialize(Map<String, dynamic>.from(doc)),
    relaxed: true,
  );
  return const JsonEncoder.withIndent('  ').convert(ejson);
}

/// Parses Extended JSON (canonical or relaxed) back into Dart BSON values.
Map<String, dynamic> mongoDocumentFromEjson(String text) {
  final decoded = json.decode(text);
  if (decoded is! Map) {
    throw const FormatException('Document JSON must be an object');
  }
  return EJsonCodec.eJson2Doc(Map<String, dynamic>.from(decoded));
}

/// Hint when a find filter's `_id` is still a JSON string (not ObjectId).
const kMongoFilterIdStringHint =
    'No documents matched. If `_id` is an ObjectId, use '
    r'{"_id": {"$oid": "…"}} or a 24-character hex `_id`.';

/// Parses a find filter: Extended JSON (`$oid`, `$date`, …) plus a 24-char
/// hex `_id` string wrapped as [ObjectId].
Map<String, dynamic> mongoFilterFromJson(String text) {
  final decoded = json.decode(text);
  if (decoded is! Map) {
    throw const FormatException('Filter JSON must be an object');
  }
  final raw = Map<String, dynamic>.from(decoded);
  Map<String, dynamic> doc;
  try {
    doc = EJsonCodec.eJson2Doc(Map<String, dynamic>.from(raw));
  } catch (_) {
    doc = raw;
  }
  final id = doc['_id'];
  if (id is String && ObjectId.isValidHexId(id)) {
    doc['_id'] = ObjectId.fromHexString(id);
  }
  return doc;
}

/// True when `_id` is still a JSON string (hex wrap did not apply).
bool mongoFilterNeedsObjectIdHint(Map<String, dynamic> filter) {
  return filter['_id'] is String;
}

/// Full-document Save payload for [DbCollection.replaceOne].
///
/// Parsed JSON minus any `_id` the user typed, then `_id` locked to
/// [originalId]. Keys absent from [parsed] (including nested ones) are not in
/// the replacement, so they are dropped — unlike `$set`, which only merges.
Map<String, dynamic> mongoFullDocumentReplacement({
  required Map<String, dynamic> parsed,
  required Object originalId,
}) {
  final out = Map<String, dynamic>.from(parsed);
  out['_id'] = originalId;
  return out;
}
