/// Whether [sql] is allowed for the table browser "custom SQL" path (read-only SELECT).
bool isAllowedMysqlSelectQuery(String sql) {
  final t = sql.trim();
  if (t.isEmpty) return false;
  final lower = t.toLowerCase();
  if (!lower.startsWith('select') && !lower.startsWith('with')) {
    return false;
  }
  // Reject naive multi-statement (semicolon-separated) scripts.
  final parts = t.split(';').where((s) => s.trim().isNotEmpty).toList();
  return parts.length <= 1;
}
