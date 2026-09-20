import 'dart:typed_data';

import 'package:mysql_client/mysql_client.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';

/// Prefer `COLUMN_TYPE` (`tinyint(1)`, `bit(8)`) over `DATA_TYPE` (`tinyint`).
String mysqlColumnSchemaType({
  required String dataType,
  required String columnType,
}) {
  final ct = columnType.trim();
  if (ct.isNotEmpty) return ct;
  return dataType;
}

/// Grid/SQL display for a MySQL cell: BOOLEAN as true/false, BIT/BLOB as `0x` hex.
String mysqlResultCellToDisplayString(
  Object? value, {
  ResultSetColumn? column,
  String? schemaDataType,
  StringInternPool? pool,
}) {
  if (value == null) {
    return pool?.intern('NULL') ?? 'NULL';
  }
  final typeName = schemaDataType ?? '';
  final binary = (column?.isBinaryPayload ?? false) ||
      (typeName.isNotEmpty && TableMutationEngine.isBinaryType(typeName));
  if (binary) {
    final hex = binaryCellToHexDisplay(value);
    return pool?.intern(hex) ?? hex;
  }
  final boolean = (column?.isBooleanTiny ?? false) ||
      (typeName.isNotEmpty && TableMutationEngine.isBoolType(typeName));
  if (boolean) {
    final shown = _boolDisplay(value.toString());
    return pool?.intern(shown) ?? shown;
  }
  return resultCellToDisplayString(value, pool);
}

/// BIT/BLOB/BINARY cell → `0xdeadbeef` (or `NULL`).
String binaryCellToHexDisplay(Object value) {
  if (value is Uint8List) {
    return _hexPrefix(value);
  }
  if (value is List<int>) {
    return _hexPrefix(Uint8List.fromList(value));
  }
  final raw = value.toString();
  final trimmed = raw.trim();
  if (trimmed == 'NULL' || trimmed == 'null') {
    return 'NULL';
  }
  if (_looksLikeHexLiteral(trimmed)) {
    var hex = trimmed;
    if (hex.startsWith(r'\x') ||
        hex.startsWith(r'\X') ||
        hex.startsWith('0x') ||
        hex.startsWith('0X')) {
      hex = hex.substring(2);
    } else if ((hex.startsWith("x'") || hex.startsWith("X'")) &&
        hex.endsWith("'")) {
      hex = hex.substring(2, hex.length - 1);
    }
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
    return '0x$clean';
  }
  return _hexPrefix(
    Uint8List.fromList(raw.codeUnits.map((u) => u & 0xFF).toList()),
  );
}

bool _looksLikeHexLiteral(String trimmed) {
  if (trimmed.startsWith('0x') ||
      trimmed.startsWith('0X') ||
      trimmed.startsWith(r'\x') ||
      trimmed.startsWith(r'\X')) {
    return true;
  }
  if ((trimmed.startsWith("x'") || trimmed.startsWith("X'")) &&
      trimmed.endsWith("'")) {
    return true;
  }
  return false;
}

String _hexPrefix(Uint8List bytes) {
  final out = StringBuffer('0x');
  for (final b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

String _boolDisplay(String raw) {
  final trimmed = raw.trim().toLowerCase();
  if (trimmed == '1' || trimmed == 'true' || trimmed == 't') {
    return 'true';
  }
  if (trimmed == '0' || trimmed == 'false' || trimmed == 'f') {
    return 'false';
  }
  return raw;
}
