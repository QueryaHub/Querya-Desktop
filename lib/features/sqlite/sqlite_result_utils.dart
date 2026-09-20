import 'dart:typed_data';

import 'package:querya_desktop/core/database/table_mutation_engine.dart';

/// Serializable row batch for [convertSqliteResultRowsToStrings] in a worker isolate.
class SqliteResultConvertJob {
  const SqliteResultConvertJob({
    required this.rowValues,
  });

  final List<List<Object?>> rowValues;
}

/// Converts SQLite result cell values to display strings off the UI thread.
List<List<String>> convertSqliteResultRowsToStrings(
    SqliteResultConvertJob job) {
  return [
    for (final row in job.rowValues)
      [for (final value in row) sqliteResultCellToDisplayString(value)],
  ];
}

/// BLOB as `X'deadbeef'`; other values via [Object.toString]. Null → `NULL`.
String sqliteResultCellToDisplayString(
  Object? value, {
  String? dataTypeName,
}) {
  if (value == null) return 'NULL';
  if (value is Uint8List) {
    return sqliteBlobHexLiteral(value);
  }
  if (value is List<int>) {
    return sqliteBlobHexLiteral(Uint8List.fromList(value));
  }
  if (dataTypeName != null &&
      dataTypeName.isNotEmpty &&
      TableMutationEngine.isBinaryType(dataTypeName)) {
    return sqliteBlobHexLiteralFromCell(value);
  }
  return value.toString();
}

/// SQLite blob literal `X'aabbcc'`.
String sqliteBlobHexLiteral(Uint8List bytes) {
  final out = StringBuffer("X'");
  for (final b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  out.write("'");
  return out.toString();
}

String sqliteBlobHexLiteralFromCell(Object value) {
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
    return sqliteBlobHexLiteral(
      Uint8List.fromList(raw.codeUnits.map((u) => u & 0xFF).toList()),
    );
  }
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
  return "X'$clean'";
}
