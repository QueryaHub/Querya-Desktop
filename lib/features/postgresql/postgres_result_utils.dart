/// Serializable row batch for [convertPostgresResultRowsToStrings] in a worker isolate.
class PostgresResultConvertJob {
  const PostgresResultConvertJob({
    required this.rowValues,
  });

  final List<List<Object?>> rowValues;
}

/// Converts PostgreSQL result cell values to display strings off the UI thread.
List<List<String>> convertPostgresResultRowsToStrings(PostgresResultConvertJob job) {
  return job.rowValues
      .map(
        (row) => row
            .map((value) => value == null ? 'NULL' : value.toString())
            .toList(),
      )
      .toList();
}
