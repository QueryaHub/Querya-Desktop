/// Serializable row batch for [convertMysqlResultRowsToStrings] in a worker isolate.
class MysqlResultConvertJob {
  const MysqlResultConvertJob({
    required this.rowValues,
  });

  final List<List<Object?>> rowValues;
}

/// Converts MySQL result cell values to display strings off the UI thread.
List<List<String>> convertMysqlResultRowsToStrings(MysqlResultConvertJob job) {
  return job.rowValues
      .map(
        (row) => row
            .map((value) => value == null ? 'NULL' : value.toString())
            .toList(),
      )
      .toList();
}
