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
