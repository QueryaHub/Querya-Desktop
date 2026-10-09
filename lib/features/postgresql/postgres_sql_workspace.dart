import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/database/postgres_sql.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_result_utils.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_utils.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';

/// Database used for this SQL workspace session (matches [PostgresService.acquire]).
String _pgSqlSessionDatabase(ConnectionRow row) {
  final d = row.databaseName?.trim();
  if (d == null || d.isEmpty) return 'postgres';
  return d;
}

/// Execution delegate for PostgreSQL connections.
class PostgresSqlExecutionDelegate extends SqlExecutionDelegate {
  PostgresSqlExecutionDelegate({
    required this.connectionRow,
    required this.isReadOnly,
    required this.effectiveDatabaseProvider,
    required this.autocommitProvider,
    this.isMcp = false,
  });

  final ConnectionRow connectionRow;
  final bool isReadOnly;

  /// MCP delegates run on the MCP session of their own, not the user's.
  final bool isMcp;

  PgSessionMode get _sessionMode => isMcp
      ? PgSessionMode.mcp
      : (isReadOnly ? PgSessionMode.readOnly : PgSessionMode.readWrite);
  final String Function() effectiveDatabaseProvider;
  final bool Function() autocommitProvider;

  PgLease? _lease;
  String? _interruptDatabase;

  PgLease? get lease => _lease;

  Future<void> ensureLease() async {
    if (_lease != null && _lease!.connection.isConnected) return;
    dropLease();
    final db = effectiveDatabaseProvider();
    final lease = await PostgresService.instance.acquire(
      connectionRow,
      database: db,
      mode: _sessionMode,
    );
    _lease = lease;
    _interruptDatabase = db;
  }

  void dropLease() {
    _lease?.release();
    _lease = null;
    _interruptDatabase = null;
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
      throw StateError('Could not connect to PostgreSQL.');
    }
    await conn.execute(command, timeout: timeout);
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
      throw StateError('Could not connect to PostgreSQL.');
    }

    final cap = limit ?? kDefaultSqlResultMaxRows;
    final effectiveSql = injectSqlLimit(sql, cap);

    if (!autocommitProvider()) {
      final inTx = await conn.inOpenTransaction() ?? false;
      if (!inTx && !shouldSkipImplicitBegin(effectiveSql)) {
        await conn.execute('BEGIN', timeout: timeout);
      }
    }

    final result = await conn.execute(effectiveSql, timeout: timeout);

    final schema = result.schema;
    final cols = <String>[];
    for (var i = 0; i < schema.columns.length; i++) {
      final c = schema.columns[i];
      cols.add(
        c.columnName?.isNotEmpty == true ? c.columnName! : '[$i]',
      );
    }

    final rawRows = <List<Object?>>[];
    var n = 0;
    for (final row in result) {
      if (n >= cap) break;
      rawRows.add(row.toList());
      n++;
    }

    final outRows = await convertPostgresResultRowsToStringsAdaptive(
      PostgresResultConvertJob(
        rowValues: rawRows,
        columnTypeOids: [
          for (final c in schema.columns) c.typeOid,
        ],
      ),
    );

    final isTruncated = result.length >= cap;
    String? statusMsg;
    if (cols.isEmpty && outRows.isEmpty) {
      statusMsg = 'Command completed. Rows affected: ${result.affectedRows}.';
    } else {
      statusMsg = isTruncated
          ? 'Showing first $cap row(s) (result capped).'
          : '${result.length} row(s).';
    }

    return SqlExecutionResult(
      columns: cols,
      rows: outRows,
      affectedRows: result.affectedRows,
      statusMessage: statusMsg,
      isTruncated: isTruncated,
    );
  }

  @override
  Future<String> explainQuery(String sql) async {
    await ensureLease();
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('Could not connect to PostgreSQL.');
    }
    final res = await conn.execute('EXPLAIN $sql');
    return res.map((r) => r.first.toString()).join('\n');
  }

  @override
  Future<void> cancelQuery() async {
    PostgresService.instance.interrupt(
      connectionRow,
      database: _interruptDatabase ?? effectiveDatabaseProvider(),
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
    if (target != null && columns.isNotEmpty) {
      return SqlResultGridSchema.fromLoad(
        await loadTableViewSchema(
          () => conn.getTableSchema(
            schema: target.schema ?? 'public',
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
      throw StateError('Could not connect to PostgreSQL.');
    }

    await runPostgresStatementsInTransaction(
      (sql) async {
        final result = await conn.execute(sql, timeout: timeout);
        if (sql != 'BEGIN' && sql != 'COMMIT' && sql != 'ROLLBACK') {
          expectDmlMatchedRows(result.affectedRows);
        }
      },
      plan.statements.map((s) => s.sql),
    );
  }

  @override
  void dispose() {
    dropLease();
  }
}

/// Ad-hoc SQL editor + results for a PostgreSQL connection (pgAdmin-style).
class PostgresSqlWorkspace extends material.StatefulWidget {
  const PostgresSqlWorkspace({
    super.key,
    required this.connectionRow,
    this.transactionOpenNotifier,
    this.postgresSqlEditorContext,
    this.postgresSqlEditorContextToken = 0,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final bool isReadOnly;

  /// Updated when transaction state changes (for tab-switch warnings).
  final material.ValueNotifier<bool?>? transactionOpenNotifier;

  /// Table/view/matview from the tree: sets session DB (if non-empty) and editor template.
  final ({
    String database,
    String schema,
    String name,
    PostgresObjectKind kind
  })? postgresSqlEditorContext;

  /// Increments when [postgresSqlEditorContext] should be re-applied to the editor.
  final int postgresSqlEditorContextToken;

  @override
  material.State<PostgresSqlWorkspace> createState() =>
      _PostgresSqlWorkspaceState();
}

class _PostgresSqlWorkspaceState extends material.State<PostgresSqlWorkspace> {
  late PostgresSqlExecutionDelegate _delegate;
  final material.GlobalKey<GenericSqlWorkspaceState> _workspaceKey =
      material.GlobalKey<GenericSqlWorkspaceState>();

  int _lastAppliedSqlContextToken = -1;
  bool _autocommit = true;

  String _effectiveSessionDatabase() {
    final ctx = widget.postgresSqlEditorContext;
    if (ctx != null) {
      final d = ctx.database.trim();
      if (d.isNotEmpty) return d;
    }
    return _pgSqlSessionDatabase(widget.connectionRow);
  }

  @override
  void initState() {
    super.initState();
    _delegate = PostgresSqlExecutionDelegate(
      connectionRow: widget.connectionRow,
      isReadOnly: widget.isReadOnly,
      effectiveDatabaseProvider: _effectiveSessionDatabase,
      autocommitProvider: () => _autocommit,
    );
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPostgresSqlTreeContext();
    });
  }

  @override
  void didUpdateWidget(covariant PostgresSqlWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _lastAppliedSqlContextToken = -1;
    }
    if (oldWidget.isReadOnly != widget.isReadOnly ||
        oldWidget.connectionRow.id != widget.connectionRow.id) {
      _delegate.dispose();
      _delegate = PostgresSqlExecutionDelegate(
        connectionRow: widget.connectionRow,
        isReadOnly: widget.isReadOnly,
        effectiveDatabaseProvider: _effectiveSessionDatabase,
        autocommitProvider: () => _autocommit,
      );
      _workspaceKey.currentState?.invalidateAllPanes();
    }
    _syncPostgresSqlTreeContext();
  }

  void _syncPostgresSqlTreeContext() {
    final ctx = widget.postgresSqlEditorContext;
    final tok = widget.postgresSqlEditorContextToken;
    if (ctx == null) {
      _lastAppliedSqlContextToken = tok;
      return;
    }
    if (tok == _lastAppliedSqlContextToken) return;
    _lastAppliedSqlContextToken = tok;
    _delegate.dropLease();

    final sql = postgresBrowseSelectSql(schema: ctx.schema, table: ctx.name);
    final ws = _workspaceKey.currentState;
    if (ws == null) return;

    if (ws.activeSession.controller.text.trim().isEmpty &&
        ws.activeSession.rows.isEmpty) {
      ws.activeSession.controller.value = material.TextEditingValue(
        text: sql,
        selection: material.TextSelection.collapsed(offset: sql.length),
      );
      ws.activeSession.title = ctx.name;
      ws.invalidatePane(ws.activeSession);
      ws.setState(() {});
    } else {
      ws.addNewTab(initialSql: sql, title: ctx.name);
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
      catalogDelegateFactory: () => PostgresSqlExecutionDelegate(
        connectionRow: widget.connectionRow,
        isReadOnly: true,
        effectiveDatabaseProvider: _effectiveSessionDatabase,
        // The catalog runs without the editor's implicit BEGIN, so opening the
        // diagram never opens a transaction in the editor.
        autocommitProvider: () => true,
      ),
      dialect: SqlDialect.postgres,
      sessionPrefix: 'pg',
      transactionOpenNotifier: widget.transactionOpenNotifier,
      isReadOnly: widget.isReadOnly,
      supportsAutocommit: true,
      initialAutocommit: _autocommit,
      onAutocommitChanged: (v) => _autocommit = v,
      supportsStmtTimeout: true,
      getStoredTimeoutSeconds: () =>
          AppSettings.instance.getPostgresSqlStmtTimeoutSeconds(),
      setStoredTimeoutSeconds: (v) =>
          AppSettings.instance.setPostgresSqlStmtTimeoutSeconds(v),
      effectiveDatabaseName: _effectiveSessionDatabase,
    );
  }
}
