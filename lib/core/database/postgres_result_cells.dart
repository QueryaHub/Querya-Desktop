import 'dart:convert';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';

/// Schema type for the grid codec: prefer `udt_name` over `data_type`.
///
/// `information_schema.columns.data_type` is `ARRAY` / `USER-DEFINED` for
/// arrays, enums, and domains — too coarse for `formatLiteral`.
String postgresColumnSchemaType({
  required String dataType,
  required String udtName,
}) {
  final dt = dataType.trim();
  final udt = udtName.trim();
  final dtLower = dt.toLowerCase();
  if (dtLower == 'array') {
    if (udt.startsWith('_') && udt.length > 1) {
      return '${udt.substring(1)}[]';
    }
    return udt.isNotEmpty ? '$udt[]' : dt;
  }
  if (dtLower == 'user-defined') {
    return udt.isNotEmpty ? udt : dt;
  }
  if (udt.isNotEmpty) return udt;
  return dt;
}

/// PG-literal-friendly cell text: ISO timestamps, `\x` hex for bytea, JSON
/// for jsonb, `{1,2,3}` for arrays. Null → `NULL`.
String postgresResultCellToDisplayString(
  Object? value, {
  int? typeOid,
  String? dataTypeName,
}) {
  if (value == null) return 'NULL';
  if (value is UndecodedBytes) return value.asString;

  if (value is Uint8List) {
    return postgresByteaHexDisplay(value);
  }
  if (_isByteaType(typeOid, dataTypeName)) {
    if (value is List<int>) {
      return postgresByteaHexDisplay(Uint8List.fromList(value));
    }
    return postgresByteaHexDisplayFromCell(value);
  }

  if (value is DateTime) {
    if (_isDateOnly(typeOid, dataTypeName)) {
      return value.toIso8601String().split('T').first;
    }
    return value.toIso8601String();
  }

  if (value is bool) return value ? 'true' : 'false';

  if (_isJsonType(typeOid, dataTypeName) || value is Map) {
    if (value is String) return value;
    try {
      return json.encode(value);
    } catch (_) {
      return value.toString();
    }
  }

  if (value is List) {
    return postgresArrayLiteral(value);
  }

  return value.toString();
}

/// PostgreSQL bytea text `\xdeadbeef`.
String postgresByteaHexDisplay(Uint8List bytes) {
  final out = StringBuffer(r'\x');
  for (final b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

String postgresByteaHexDisplayFromCell(Object value) {
  final raw = value.toString().trim();
  if (raw == 'NULL' || raw == 'null') return 'NULL';
  var hex = raw;
  if (hex.startsWith(r'\x') ||
      hex.startsWith(r'\X') ||
      hex.startsWith('0x') ||
      hex.startsWith('0X')) {
    hex = hex.substring(2);
  } else if ((hex.startsWith("x'") || hex.startsWith("X'")) &&
      hex.endsWith("'")) {
    hex = hex.substring(2, hex.length - 1);
  } else {
    return postgresByteaHexDisplay(
      Uint8List.fromList(raw.codeUnits.map((u) => u & 0xFF).toList()),
    );
  }
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
  return '\\x$clean';
}

/// PostgreSQL array text `{1,2,3}` / `{Alpha,"a b"}` (not Dart `[…]`).
String postgresArrayLiteral(List<dynamic> items) {
  final inner = items.map(_postgresArrayElement).join(',');
  return '{$inner}';
}

String _postgresArrayElement(Object? e) {
  if (e == null) return 'NULL';
  if (e is Uint8List) return postgresByteaHexDisplay(e);
  if (e is List) return postgresArrayLiteral(e);
  if (e is Map) {
    return _postgresArrayQuote(json.encode(e));
  }
  if (e is DateTime) return e.toIso8601String();
  if (e is bool) return e ? 't' : 'f';
  if (e is String) return _postgresArrayQuote(e);
  return e.toString();
}

String _postgresArrayQuote(String s) {
  return '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

bool _isByteaType(int? typeOid, String? dataTypeName) {
  if (typeOid != null && typeOid == Type.byteArray.oid) return true;
  final t = dataTypeName?.toLowerCase() ?? '';
  if (_isPgArrayTypeName(t)) return false;
  return t.contains('bytea');
}

bool _isJsonType(int? typeOid, String? dataTypeName) {
  if (typeOid != null &&
      (typeOid == Type.json.oid || typeOid == Type.jsonb.oid)) {
    return true;
  }
  final t = dataTypeName?.toLowerCase() ?? '';
  if (_isPgArrayTypeName(t)) return false;
  return t.contains('json');
}

bool _isDateOnly(int? typeOid, String? dataTypeName) {
  if (typeOid != null && typeOid == Type.date.oid) return true;
  final t = dataTypeName?.toLowerCase().trim() ?? '';
  return t == 'date';
}

bool _isPgArrayTypeName(String lower) {
  return lower.contains('[]') ||
      (lower.startsWith('_') && !lower.contains(' '));
}
