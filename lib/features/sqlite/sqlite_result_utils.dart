import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';

/// Serializable row batch for [convertSqliteResultRowsToStrings] in a worker isolate.
class SqliteResultConvertJob {
  const SqliteResultConvertJob({
    required this.rowValues,
    this.columnDataTypes,
  });

  final List<List<Object?>> rowValues;
  final List<String?>? columnDataTypes;
}

/// Converts SQLite result cell values to display strings off the UI thread.
List<List<String>> convertSqliteResultRowsToStrings(
    SqliteResultConvertJob job) {
  final types = job.columnDataTypes;
  return [
    for (final row in job.rowValues)
      [
        for (var i = 0; i < row.length; i++)
          sqliteResultCellToDisplayString(
            row[i],
            dataTypeName: types != null && i < types.length ? types[i] : null,
          ),
      ],
  ];
}

/// Typed conversion in a single pass: converts each cell to SQLite display string,
/// interns the resulting string (repeated values share one instance), and yields
/// to the event loop every [yieldEvery] rows.
Future<List<List<String>>> convertSqliteResultRowsToStringsAdaptive(
  SqliteResultConvertJob job, {
  int yieldEvery = kResultStringConvertYieldEvery,
  StringInternPool? pool,
}) async {
  final rowValues = job.rowValues;
  if (rowValues.isEmpty) return const [];

  final types = job.columnDataTypes;
  final activePool = pool ?? StringInternPool();
  final out = <List<String>>[];
  for (var r = 0; r < rowValues.length; r++) {
    final row = rowValues[r];
    out.add([
      for (var i = 0; i < row.length; i++)
        activePool.intern(
          sqliteResultCellToDisplayString(
            row[i],
            dataTypeName: types != null && i < types.length ? types[i] : null,
            pool: activePool,
          ),
        ),
    ]);
    if (yieldEvery > 0 && (r + 1) % yieldEvery == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return out;
}

/// BLOB as `X'deadbeef'`; other values via [Object.toString]. Null → `NULL`.
String sqliteResultCellToDisplayString(
  Object? value, {
  String? dataTypeName,
  StringInternPool? pool,
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
  if (pool != null) {
    return pool.internObject(value);
  }
  if (value is bool) return value ? 'true' : 'false';
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
