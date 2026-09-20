import 'package:querya_desktop/core/database/postgres_result_cells.dart';

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
