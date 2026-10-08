import 'dart:async';

import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

/// Synthetic [SqlExecutionDelegate] for `GenericSqlWorkspace` tests: records
/// every call and answers with scripted results.
class FakeSqlExecutionDelegate extends SqlExecutionDelegate {
  FakeSqlExecutionDelegate({this.onExecute});

  /// Scripted answer per statement; defaults to a one-row `SELECT`-like result.
  SqlExecutionResult Function(String sql)? onExecute;

  /// When set, `executeQuery` waits for it before answering (to keep a query
  /// "running").
  Completer<void>? gate;

  /// Plan returned by `explainQuery`; throws it when it is an [Exception].
  String explainPlan = 'plan';
  Object? explainError;

  /// When true, `cancelQuery` aborts a query held by [gate] like a driver would.
  bool cancelAbortsGate = false;

  bool explainSupported = true;
  bool cancelSupported = true;

  final executed = <String>[];
  final explained = <String>[];
  final appliedPlans = <TableMutationPlan>[];
  var cancelCount = 0;
  var disposeCount = 0;

  @override
  Future<SqlExecutionResult> executeQuery(
    String sql, {
    int? limit,
    Duration? timeout,
  }) async {
    executed.add(sql);
    final pending = gate;
    if (pending != null) await pending.future;
    final scripted = onExecute;
    if (scripted != null) return scripted(sql);
    return const SqlExecutionResult(
      columns: ['n'],
      rows: [
        ['1'],
      ],
    );
  }

  @override
  Future<String> explainQuery(String sql) async {
    explained.add(sql);
    final error = explainError;
    if (error != null) throw error;
    return explainPlan;
  }

  @override
  bool get supportsExplain => explainSupported;

  @override
  Future<void> cancelQuery() async {
    cancelCount++;
    final pending = gate;
    if (cancelAbortsGate && pending != null && !pending.isCompleted) {
      pending.completeError(StateError('canceling statement due to user request'));
    }
  }

  @override
  bool get supportsCancel => cancelSupported;

  @override
  bool get supportsTransactions => false;

  @override
  Future<void> applyStagedMutations({
    required TableMutationPlan plan,
    Duration? timeout,
  }) async {
    appliedPlans.add(plan);
  }

  @override
  void dispose() => disposeCount++;
}
