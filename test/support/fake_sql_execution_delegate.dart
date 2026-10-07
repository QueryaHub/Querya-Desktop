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

  final executed = <String>[];
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
  Future<String> explainQuery(String sql) async => 'plan';

  @override
  Future<void> cancelQuery() async => cancelCount++;

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
