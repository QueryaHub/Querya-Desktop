import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/database/sql_limit.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/database/sqlite_sql.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/sqlite/sqlite_result_utils.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/features/workspace/query_plan.dart';

/// Execution delegate for SQLite connections.
class SqliteSqlExecutionDelegate extends SqlExecutionDelegate {
  SqliteSqlExecutionDelegate({
    required this.connectionRow,
    required this.isReadOnly,
    this.isMcp = false,
  });

  final ConnectionRow connectionRow;
  final bool isReadOnly;

  /// MCP delegates run on the MCP session of their own, not the user's.
  final bool isMcp;

  SqliteSessionMode get _sessionMode => isMcp
      ? SqliteSessionMode.mcp
      : (isReadOnly ? SqliteSessionMode.readOnly : SqliteSessionMode.readWrite);

  SqliteLease? _lease;

  SqliteLease? get lease => _lease;

  Future<void> ensureLease() async {
    if (_lease != null && _lease!.connection.isConnected) return;
    _lease?.release();
    _lease = null;
    final lease = await SqliteService.instance.acquire(
      connectionRow,
      mode: _sessionMode,
    );
    _lease = lease;
  }

  void dropLease() {
    _lease?.release();
    _lease = null;
  }

  @override
  bool get supportsTransactions => true;

  @override
  Future<bool?> checkTransactionOpen() async {
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) {
      return null;
    }
    return conn.inOpenTransaction();
  }

  @override
  Future<void> runTransactionCommand(String command, {Duration? timeout}) async {
    await ensureLease();
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('Could not connect to SQLite.');
    }
    await conn.executeWithTimeout(command, timeout: timeout);
  }

  @override
  Future<SqlExecutionResult> executeQuery(
    String sql, {
    int? limit,
    Duration? timeout,
  }) async {
    await ensureLease();
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('Could not connect to SQLite.');
    }

    final cap = limit ?? kDefaultSqlResultMaxRows;
    final effectiveSql = sqliteSqlIsReadOnlyQuery(sql)
        ? injectSqlLimit(sql, cap)
        : sql;

    final results = await conn.executeWithTimeout(effectiveSql, timeout: timeout);

    final cols = <String>[];
    if (results.isNotEmpty) {
      cols.addAll(results.first.keys);
    } else if (sqliteSqlIsReadOnlyQuery(sql)) {
      cols.addAll(await conn.inferQueryColumns(sql));
    }

    final truncated = results.length > cap;
    final limitCount = truncated ? cap : results.length;
    final injectedLimit = effectiveSql != sql;

    final rawRows = results.take(limitCount).map((row) {
      return cols
          .map((col) => sqliteResultCellToDisplayString(row[col]))
          .toList();
    }).toList();

    final outRows = await convertResultRowsToStringsAdaptive(rawRows);

    String? statusMsg;
    if (cols.isEmpty && outRows.isEmpty) {
      statusMsg = 'Command completed.';
    } else if (truncated || (injectedLimit && results.length >= cap)) {
      statusMsg = 'Showing first $cap row(s) (result capped).';
    } else {
      statusMsg = '${results.length} row(s).';
    }

    return SqlExecutionResult(
      columns: cols,
      rows: outRows,
      statusMessage: statusMsg,
      isTruncated: truncated || (injectedLimit && results.length >= cap),
    );
  }

  @override
  Future<PlanNode?> explainTree(String sql) async {
    await ensureLease();
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) return null;
    final res = await conn.executeWithTimeout('EXPLAIN QUERY PLAN $sql');
    return QueryPlanParser.fromSqliteRows([
      for (final r in res)
        (
          id: int.parse('${r.values.elementAt(0)}'),
          parent: int.parse('${r.values.elementAt(1)}'),
          detail: '${r.values.elementAt(3)}',
        ),
    ]);
  }

  @override
  Future<String> explainQuery(String sql) async {
    await ensureLease();
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('Could not connect to SQLite.');
    }
    final res = await conn.executeWithTimeout('EXPLAIN QUERY PLAN $sql');
    return res.map((r) => r.values.join(' | ')).join('\n');
  }

  @override
  Future<void> cancelQuery() async {
    await _lease?.connection.forceClose();
    dropLease();
  }

  @override
  Future<SqlResultGridSchema> resolveTableSchema(
    String userSql,
    List<String> columns,
  ) async {
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) {
      return SqlResultGridSchema.none;
    }
    final target = SqlTableTargetExtractor.extract(userSql);
    if (target != null && columns.isNotEmpty) {
      var isView = false;
      try {
        final kind = await conn.execute(
          'SELECT type FROM sqlite_master WHERE name = ?',
          [target.tableName],
        );
        isView = kind.isNotEmpty && kind.first['type'] == 'view';
      } catch (_) {}

      return SqlResultGridSchema.fromLoad(
        await loadTableViewSchema(
          () => conn.getTableSchema(table: target.tableName),
        ),
        sqliteImplicitRowid: !isView,
      );
    }
    return SqlResultGridSchema.none;
  }

  @override
  Future<void> applyStagedMutations({
    required TableMutationPlan plan,
    Duration? timeout,
  }) async {
    await ensureLease();
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('Could not connect to SQLite.');
    }

    await conn.runInTransaction(() async {
      for (final stmt in plan.statements) {
        expectDmlMatchedRows(await conn.executeAffected(stmt.sql));
      }
    });
  }

  @override
  void dispose() {
    dropLease();
  }
}

/// Ad-hoc SQL editor + results for SQLite.
class SqliteSqlWorkspace extends material.StatefulWidget {
  const SqliteSqlWorkspace({
    super.key,
    required this.connectionRow,
    this.transactionOpenNotifier,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final bool isReadOnly;

  /// Updated when transaction state changes (for tab-switch warnings).
  final material.ValueNotifier<bool?>? transactionOpenNotifier;

  @override
  material.State<SqliteSqlWorkspace> createState() =>
      _SqliteSqlWorkspaceState();
}

class _SqliteSqlWorkspaceState extends material.State<SqliteSqlWorkspace> {
  late SqliteSqlExecutionDelegate _delegate;
  final material.GlobalKey<GenericSqlWorkspaceState> _workspaceKey =
      material.GlobalKey<GenericSqlWorkspaceState>();

  @material.visibleForTesting
  int get paneBuildCount => _workspaceKey.currentState?.paneBuildCount ?? 0;

  @material.visibleForTesting
  set paneBuildCount(int value) {
    final ws = _workspaceKey.currentState;
    if (ws != null) {
      ws.paneBuildCount = value;
    }
  }

  @material.visibleForTesting
  SqlQueryTabSession get activeSession => _workspaceKey.currentState!.activeSession;

  @material.visibleForTesting
  void debugRebuildActivePane() {
    _workspaceKey.currentState?.debugRebuildActivePane();
  }

  @override
  void initState() {
    super.initState();
    _delegate = SqliteSqlExecutionDelegate(
      connectionRow: widget.connectionRow,
      isReadOnly: widget.isReadOnly,
    );
  }

  @override
  void didUpdateWidget(covariant SqliteSqlWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isReadOnly != widget.isReadOnly ||
        oldWidget.connectionRow.id != widget.connectionRow.id) {
      _delegate.dispose();
      _delegate = SqliteSqlExecutionDelegate(
        connectionRow: widget.connectionRow,
        isReadOnly: widget.isReadOnly,
      );
      _workspaceKey.currentState?.invalidateAllPanes();
    }
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return GenericSqlWorkspace(
      key: _workspaceKey,
      connectionRow: widget.connectionRow,
      delegate: _delegate,
      catalogDelegateFactory: () => SqliteSqlExecutionDelegate(
        connectionRow: widget.connectionRow,
        isReadOnly: true,
      ),
      dialect: SqlDialect.sqlite,
      sessionPrefix: 'sqlite',
      transactionOpenNotifier: widget.transactionOpenNotifier,
      isReadOnly: widget.isReadOnly,
      supportsAutocommit: false,
      supportsStmtTimeout: true,
      getStoredTimeoutSeconds: () =>
          AppSettings.instance.getSqliteSqlStmtTimeoutSeconds(),
      setStoredTimeoutSeconds: (v) =>
          AppSettings.instance.setSqliteSqlStmtTimeoutSeconds(v),
      effectiveDatabaseName: () => widget.connectionRow.databaseName ?? '',
    );
  }
}
