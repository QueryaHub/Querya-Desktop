import 'dart:convert';

/// Display string for a MongoDB document field in the Cell Inspector.
String mongoFieldToDisplay(Object? value) {
  if (value == null) return 'NULL';
  if (value is Map || value is List) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
  if (value is bool || value is num) return value.toString();
  if (value is String) return value;
  return value.toString();
}

/// Parses an inspector string back into a BSON-JSON-friendly Dart value.
Object? mongoDisplayToValue(String text) {
  if (text == 'NULL') return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed == 'true') return true;
  if (trimmed == 'false') return false;
  final asNum = num.tryParse(trimmed);
  if (asNum != null) return asNum;
  if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
      (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
    try {
      return json.decode(trimmed);
    } catch (_) {
      return text;
    }
  }
  return text;
}
