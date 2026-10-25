import 'package:mongo_dart/mongo_dart.dart' show BsonBinary, ObjectId;

/// How a BSON value reads in the Table and Tree views. The driver hands back
/// Dart objects for some types (`BsonBinary`, a regular expression, `Int64`,
/// `Decimal`); their `toString()` is a Dart debug string (`BsonBinary(deadbeef)`,
/// `RegExp: pattern=…`), not something to show a user (#1826).
String mongoValueText(Object? value) {
  if (value == null) return 'null';
  if (value is BsonBinary) return 'Binary(0x${value.hexString})';
  if (value is RegExp) return mongoRegexText(value);
  return value.toString();
}

/// `/pattern/flags`, as the mongo shell writes a regular expression.
String mongoRegexText(RegExp regex) {
  final flags = '${regex.isCaseSensitive ? '' : 'i'}'
      '${regex.isMultiLine ? 'm' : ''}'
      '${regex.isDotAll ? 's' : ''}';
  return '/${regex.pattern}/$flags';
}

/// Whether [value] is a number of any BSON numeric type. `Int64` and `Decimal`
/// are not Dart [num]s.
bool mongoValueIsNumber(Object? value) =>
    value is num || _isNamed(value, const {'Int64', 'Decimal'});

/// The short type name of the chip in the Tree view.
String mongoValueTypeChip(Object? value) {
  if (value == null) return 'null';
  if (value is String) return 'str';
  if (value is int) return 'int';
  if (value is double) return 'dbl';
  if (value is bool) return 'bool';
  if (value is ObjectId) return 'oid';
  if (value is DateTime) return 'date';
  if (value is BsonBinary) return 'bin';
  if (value is RegExp) return 'regex';
  if (_isNamed(value, const {'Int64'})) return 'long';
  if (_isNamed(value, const {'Decimal'})) return 'dec';
  return value.runtimeType.toString();
}

/// The type shown in the Table view's column tooltip.
String mongoValueTypeName(Object value) {
  if (value is BsonBinary) return 'Binary';
  if (value is RegExp) return 'Regex';
  return value.runtimeType.toString();
}

bool _isNamed(Object? value, Set<String> names) =>
    value != null && names.contains(value.runtimeType.toString());
