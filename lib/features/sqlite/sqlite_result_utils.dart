/// Serializable row batch for [convertSqliteResultRowsToStrings] in a worker isolate.
class SqliteResultConvertJob {
  const SqliteResultConvertJob({
    required this.rowValues,
  });

  final List<List<Object?>> rowValues;
}

/// Converts SQLite result cell values to display strings off the UI thread.
List<List<String>> convertSqliteResultRowsToStrings(SqliteResultConvertJob job) {
  return job.rowValues
      .map(
        (row) => row
            .map((value) => value == null ? 'NULL' : value.toString())
            .toList(),
      )
      .toList();
}
