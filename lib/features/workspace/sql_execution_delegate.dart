import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/workspace/sql_result_grid_schema.dart';

/// Strategy/delegate contract for executing queries, transactions and DML mutations
/// across different DBMS drivers in [GenericSqlWorkspace].
abstract class SqlExecutionDelegate {
  /// Executes a query statement and returns columns, rows, affected count, and status details.
  Future<SqlExecutionResult> executeQuery(
    String sql, {
    int? limit,
    Duration? timeout,
  });

  /// Explains the SQL query plan if supported by the DBMS.
  Future<String> explainQuery(String sql);

  /// Whether [explainQuery] works for this driver (shows the Explain button).
  bool get supportsExplain => true;

  /// Interrupts or cancels active query execution.
  Future<void> cancelQuery();

  /// Whether [cancelQuery] really interrupts a running statement (shows the
  /// Cancel button while a query runs).
  bool get supportsCancel => true;

  /// Whether the database supports explicit multi-statement transactions.
  bool get supportsTransactions;

  /// Runs an explicit transaction statement such as `BEGIN`, `COMMIT`, `ROLLBACK`.
  Future<void> runTransactionCommand(String command, {Duration? timeout}) =>
      Future.value();

  /// Refreshes and returns the open transaction state (`true` = in open tx, `false` = no tx, `null` = unknown).
  Future<bool?> checkTransactionOpen() => Future.value(null);

  /// Resolves the schema (primary keys, column types, metadata) for a targeted table if applicable.
  Future<SqlResultGridSchema> resolveTableSchema(
    String userSql,
    List<String> columns,
  ) =>
      Future.value(SqlResultGridSchema.none);

  /// Applies staged DML mutations in a single atomic transaction.
  Future<void> applyStagedMutations({
    required TableMutationPlan plan,
    Duration? timeout,
  }) =>
      Future.error(UnsupportedError('DML mutations are not supported'));

  /// Releases resources (leases, connections, listeners) held by the delegate.
  void dispose() {}
}

/// Result returned by [SqlExecutionDelegate.executeQuery].
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
