/// Utilities for PostgreSQL table data view (quoting, row conversion).
library;

/// Quotes a PostgreSQL identifier (e.g. schema or table name).
/// Doubles any internal double-quote.
String quotePostgresIdentifier(String name) {
  return '"${name.replaceAll('"', '""')}"';
}

/// Converts raw result rows (list of dynamic values per row) to list of string rows.
List<List<String>> convertResultRowsToStrings(List<List<dynamic>> rawRows) {
  return rawRows.map((row) {
    return row.map((value) {
      if (value == null) return 'NULL';
      if (value is DateTime) return value.toIso8601String();
      return value.toString();
    }).toList();
  }).toList();
}
