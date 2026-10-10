import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mysql_result_cells.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/database/sql_limit.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';
import 'package:querya_desktop/core/database/stream_take_drain.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/features/workspace/query_plan.dart';

/// Execution delegate for MySQL / MariaDB connections.
class MysqlSqlExecutionDelegate extends BaseSqlExecutionDelegate {
  MysqlSqlExecutionDelegate({
    required this.connectionRow,
    required this.isReadOnly,
    this.isMcp = false,
  });

  final ConnectionRow connectionRow;
  final bool isReadOnly;

  /// MCP delegates run on the MCP session of their own, not the user's.
  final bool isMcp;

  MysqlSessionMode get _sessionMode => isMcp
      ? MysqlSessionMode.mcp
      : (isReadOnly ? MysqlSessionMode.readOnly : MysqlSessionMode.readWrite);

  MysqlLease? _lease;

  MysqlLease? get lease => _lease;

  String get poolDatabaseKey => connectionRow.databaseName ?? '';

  Future<void> ensureLease() async {
    if (_lease != null && _lease!.connection.isConnected) return;
    _lease?.release();
    _lease = null;
    final lease = await MysqlService.instance.acquire(
      connectionRow,
      database: poolDatabaseKey,
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
      throw StateError('Could not connect to MySQL.');
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
      throw StateError('Could not connect to MySQL.');
    }

    final cap = limit ?? kDefaultSqlResultMaxRows;
    final effectiveSql = injectSqlLimit(sql, cap);
    final rs = await conn.executeWithTimeout(effectiveSql, timeout: timeout, iterable: true);

    final cols = <String>[];
    for (final c in rs.cols) {
      cols.add(c.name.isNotEmpty ? c.name : 'col_${cols.length}');
    }

    final taken = await takeThenDrain(
      rs.rowsStream,
      cap,
      onProgress: (n) async {
        if (n % kResultStringConvertYieldEvery == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      },
    );
    final colList = rs.cols.toList();
    final pool = StringInternPool();
    final outRows = <List<String>>[];
    for (var r = 0; r < taken.items.length; r++) {
      final row = taken.items[r];
      outRows.add(
        List.generate(
          row.numOfColumns,
          (i) {
            final col = i < colList.length ? colList[i] : null;
            return mysqlResultCellToDisplayString(
              row.colAt(i),
              column: col,
              pool: pool,
            );
          },
        ),
      );
      if (kResultStringConvertYieldEvery > 0 &&
          (r + 1) % kResultStringConvertYieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    final truncated =
        taken.truncated || (effectiveSql != sql && outRows.length >= cap);
    final n = outRows.length;

    int? affected;
    if (cols.isEmpty && outRows.isEmpty) {
      affected = _affectedInt(rs.affectedRows);
    }

    final statusMsg = formatStatusMessage(
      columnCount: cols.length,
      rowCount: n,
      affectedRows: affected,
      isTruncated: truncated,
      cap: cap,
    );

    return SqlExecutionResult(
      columns: cols,
      rows: outRows,
      affectedRows: affected,
      statusMessage: statusMsg,
      isTruncated: truncated,
    );
  }

  static int? _affectedInt(BigInt v) {
    if (v == BigInt.zero) return null;
    return v.toInt();
  }

  @override
  Future<PlanNode?> explainTree(String sql) async {
    await ensureLease();
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) return null;
    final rs = await conn.executeWithTimeout('EXPLAIN FORMAT=JSON $sql');
    if (rs.rows.isEmpty) return null;
    return QueryPlanParser.fromMysqlJson(rs.rows.first.assoc().values.first);
  }

  @override
  Future<String> explainQuery(String sql) async {
    await ensureLease();
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('Could not connect to MySQL.');
    }
    final rs = await conn.executeWithTimeout('EXPLAIN $sql');
    final sb = StringBuffer();
    for (final row in rs.rows) {
      sb.writeln(row.assoc().entries.map((e) => '${e.key}: ${e.value}').join(', '));
    }
    return sb.toString();
  }

  @override
  Future<void> cancelQuery() async {
    MysqlService.instance.interrupt(
      connectionRow,
      database: poolDatabaseKey,
      mode: _sessionMode,
    );
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
    final schemaName = target?.schema ?? poolDatabaseKey;
    if (target != null && columns.isNotEmpty && schemaName.isNotEmpty) {
      return SqlResultGridSchema.fromLoad(
        await loadTableViewSchema(
          () => conn.getTableSchema(
            database: schemaName,
            table: target.tableName,
          ),
        ),
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
      throw StateError('Could not connect to MySQL.');
    }

    await conn.runInTransaction(() async {
      for (final stmt in plan.statements) {
        final rs = await conn.execute(stmt.sql);
        expectDmlMatchedRows(rs.affectedRows.toInt());
      }
    });
  }

  @override
  void dispose() {
    dropLease();
  }
}

/// Ad-hoc SQL editor + results for MySQL / MariaDB.
class MysqlSqlWorkspace extends material.StatefulWidget {
  const MysqlSqlWorkspace({
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
  material.State<MysqlSqlWorkspace> createState() => _MysqlSqlWorkspaceState();
}

class _MysqlSqlWorkspaceState extends material.State<MysqlSqlWorkspace> {
  late MysqlSqlExecutionDelegate _delegate;
  final material.GlobalKey<GenericSqlWorkspaceState> _workspaceKey =
      material.GlobalKey<GenericSqlWorkspaceState>();

  @override
  void initState() {
    super.initState();
    _delegate = MysqlSqlExecutionDelegate(
      connectionRow: widget.connectionRow,
      isReadOnly: widget.isReadOnly,
    );
  }

  @override
  void didUpdateWidget(covariant MysqlSqlWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isReadOnly != widget.isReadOnly ||
        oldWidget.connectionRow.id != widget.connectionRow.id) {
      _delegate.dispose();
      _delegate = MysqlSqlExecutionDelegate(
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
      catalogDelegateFactory: () => MysqlSqlExecutionDelegate(
        connectionRow: widget.connectionRow,
        isReadOnly: true,
      ),
      dialect: SqlDialect.mysql,
      sessionPrefix: 'mysql',
      transactionOpenNotifier: widget.transactionOpenNotifier,
      isReadOnly: widget.isReadOnly,
      supportsAutocommit: false,
      supportsStmtTimeout: true,
      getStoredTimeoutSeconds: () =>
          AppSettings.instance.getMysqlSqlStmtTimeoutSeconds(),
      setStoredTimeoutSeconds: (v) =>
          AppSettings.instance.setMysqlSqlStmtTimeoutSeconds(v),
      effectiveDatabaseName: () => widget.connectionRow.databaseName ?? '',
    );
  }
}
