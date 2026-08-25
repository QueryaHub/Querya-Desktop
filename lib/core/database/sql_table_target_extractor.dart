/// Result of extracting target table and schema from an SQL query.
class SqlTableTarget {
  const SqlTableTarget({
    required this.tableName,
    this.schema,
  });

  final String tableName;
  final String? schema;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SqlTableTarget &&
          tableName == other.tableName &&
          schema == other.schema;

  @override
  int get hashCode => Object.hash(tableName, schema);
}

/// Helper utility to infer the primary target table from a simple SELECT query.
abstract final class SqlTableTargetExtractor {
  static final _fromTableRegex = RegExp(
    r'\bfrom\s+(?:(?:"([^"]+)"|`([^`]+)`|([a-zA-Z_]\w*))\.)?(?:"([^"]+)"|`([^`]+)`|([a-zA-Z_]\w*))',
    caseSensitive: false,
  );

  /// Extracts the target schema and table name from [sql].
  /// Returns `null` if no simple target table can be determined (e.g. subqueries, joins).
  static SqlTableTarget? extract(String sql) {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) return null;

    // If query has JOIN or multiple tables separated by comma, avoid auto-generating DML
    final hasJoin = RegExp(r'\bjoin\b', caseSensitive: false).hasMatch(trimmed);
    if (hasJoin) return null;

    final match = _fromTableRegex.firstMatch(trimmed);
    if (match == null) return null;

    final schema = match.group(1) ?? match.group(2) ?? match.group(3);
    final table = match.group(4) ?? match.group(5) ?? match.group(6);

    if (table == null || table.isEmpty) return null;

    return SqlTableTarget(
      tableName: table,
      schema: schema,
    );
  }
}
