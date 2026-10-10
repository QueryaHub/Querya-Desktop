import 'package:flutter/foundation.dart';

/// Read side of a SQL session: run a statement, explain it, release it.
///
/// Core code that only reads (MCP, the schema catalog) depends on this and not
/// on the SQL workspace's `SqlExecutionDelegate`, which implements it.
abstract interface class SqlQueryRunner {
  /// Executes a statement and returns columns, rows, affected count and status.
  Future<SqlExecutionResult> executeQuery(
    String sql, {
    int? limit,
    Duration? timeout,
  });

  /// Explains the SQL query plan if supported by the DBMS.
  Future<String> explainQuery(String sql);

  /// Whether [explainQuery] works for this driver.
  bool get supportsExplain;

  /// Releases resources (leases, connections, listeners) held by the runner.
  void dispose();
}

/// Result returned by [SqlQueryRunner.executeQuery].
@immutable
class SqlExecutionResult {
  const SqlExecutionResult({
    this.columns = const [],
    this.rows = const [],
    this.affectedRows,
    this.statusMessage,
    this.elapsed,
    this.isTruncated = false,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final int? affectedRows;
  final String? statusMessage;
  final Duration? elapsed;
  final bool isTruncated;
}
