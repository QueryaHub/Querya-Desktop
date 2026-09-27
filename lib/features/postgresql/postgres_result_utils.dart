import 'package:querya_desktop/core/database/postgres_result_cells.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';

/// Serializable row batch for [convertPostgresResultRowsToStrings].
class PostgresResultConvertJob {
  const PostgresResultConvertJob({
    required this.rowValues,
    this.columnTypeOids,
    this.columnDataTypes,
  });

  final List<List<Object?>> rowValues;
  final List<int>? columnTypeOids;
  final List<String?>? columnDataTypes;
}

/// Converts PostgreSQL result cells to PG-literal-friendly display strings.
List<List<String>> convertPostgresResultRowsToStrings(
    PostgresResultConvertJob job) {
  final oids = job.columnTypeOids;
  final types = job.columnDataTypes;
  return [
    for (final row in job.rowValues)
      [
        for (var i = 0; i < row.length; i++)
          postgresResultCellToDisplayString(
            row[i],
            typeOid: oids != null && i < oids.length ? oids[i] : null,
            dataTypeName: types != null && i < types.length ? types[i] : null,
          ),
      ],
  ];
}

/// Typed conversion in a single pass: converts each cell with its PG type,
/// interns the resulting string (repeated enum / status values share one
/// instance) and yields to the event loop every [yieldEvery] rows.
///
/// Rows are already strings after this, so callers must not run them through
/// [convertResultRowsToStringsAdaptive] again: that would walk (and, from 1000
/// rows, copy to an isolate) the whole matrix a second time without being able
/// to recover any type information.
Future<List<List<String>>> convertPostgresResultRowsToStringsAdaptive(
  PostgresResultConvertJob job, {
  int yieldEvery = kResultStringConvertYieldEvery,
  StringInternPool? pool,
}) async {
  final rowValues = job.rowValues;
  if (rowValues.isEmpty) return const [];

  final oids = job.columnTypeOids;
  final types = job.columnDataTypes;
  final activePool = pool ?? StringInternPool();
  final out = <List<String>>[];
  for (var r = 0; r < rowValues.length; r++) {
    final row = rowValues[r];
    out.add([
      for (var i = 0; i < row.length; i++)
        activePool.intern(
          postgresResultCellToDisplayString(
            row[i],
            typeOid: oids != null && i < oids.length ? oids[i] : null,
            dataTypeName: types != null && i < types.length ? types[i] : null,
          ),
        ),
    ]);
    if (yieldEvery > 0 && (r + 1) % yieldEvery == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return out;
}
