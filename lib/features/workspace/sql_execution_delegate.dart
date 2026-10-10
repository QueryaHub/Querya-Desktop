import 'dart:async';

import 'package:querya_desktop/features/workspace/query_plan.dart';
import 'package:querya_desktop/core/database/sql_query_runner.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/workspace/sql_result_grid_schema.dart';

export 'package:querya_desktop/core/database/sql_query_runner.dart';

/// Strategy/delegate contract for executing queries, transactions and DML mutations
/// across different DBMS drivers in [GenericSqlWorkspace].
abstract class SqlExecutionDelegate implements SqlQueryRunner {
  /// Executes a query statement and returns columns, rows, affected count, and status details.
  @override
  Future<SqlExecutionResult> executeQuery(
    String sql, {
    int? limit,
    Duration? timeout,
  });

  /// Explains the SQL query plan if supported by the DBMS.
  @override
  Future<String> explainQuery(String sql);

  /// The plan as a tree, when the driver can give one. [explainQuery] remains
  /// the text fallback.
  Future<PlanNode?> explainTree(String sql) async => null;

  /// Whether [explainQuery] works for this driver (shows the Explain button).
  @override
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
  @override
  void dispose() {}
}
