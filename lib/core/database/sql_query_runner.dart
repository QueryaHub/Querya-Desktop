import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/database/compact_result_dataset.dart';

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
    this.dataset,
  });

  /// Creates a [SqlExecutionResult] backed by a [CompactResultDataset].
  ///
  /// [rows] defaults to [dataset.asLazyRowList()], providing unformatted on-demand
  /// access to cells for virtualized grid rendering while avoiding upfront
  /// allocation of millions of string objects.
  factory SqlExecutionResult.fromDataset({
    required CompactResultDataset dataset,
    int? affectedRows,
    String? statusMessage,
    Duration? elapsed,
    bool isTruncated = false,
    List<List<String>>? rows,
  }) {
    return SqlExecutionResult(
      columns: dataset.columnNames,
      rows: rows ?? dataset.asLazyRowList(),
      affectedRows: affectedRows,
      statusMessage: statusMessage,
      elapsed: elapsed,
      isTruncated: isTruncated,
      dataset: dataset,
    );
  }

  final List<String> columns;
  final List<List<String>> rows;
  final int? affectedRows;
  final String? statusMessage;
  final Duration? elapsed;
  final bool isTruncated;
  final CompactResultDataset? dataset;
}
