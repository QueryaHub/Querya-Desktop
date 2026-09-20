import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_editor_dialog.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_privileges_dialog.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_toolbar.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_utils.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

class PostgresTableView extends material.StatefulWidget {
  const PostgresTableView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.schema,
    required this.tableName,
    this.isView = false,
    this.isMaterializedView = false,
    this.limit = kPostgresBrowseDefaultRowLimit,
    this.onNavigateHome,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String schema;
  final String tableName;
  final bool isView;
  final VoidCallback? onNavigateHome;

  /// When true, toolbar offers REFRESH MATERIALIZED VIEW and matview label.
  final bool isMaterializedView;
  final int limit;

  @override
  material.State<PostgresTableView> createState() => _PostgresTableViewState();
}

class _PostgresTableViewState extends material.State<PostgresTableView> {
  PgLease? _lease;
  PostgresConnection? get _connection => _lease?.connection;

  bool _loading = true;
  String? _error;

  List<String> _columnNames = [];
  List<List<String>> _rows = [];

  /// Rows on the current page (same as _rows.length when not loading).
  int _rowsOnPage = 0;

  /// Total rows in table/view (from COUNT(*)).
  int? _totalRowCount;

  /// Zero-based offset for LIMIT/OFFSET pagination.
  int _offset = 0;

  /// When true, [dataSql] comes from [_customSql] (no pagination).
  bool _customSqlActive = false;
  String? _customSql;

  DataGridStagingBuffer? _stagingBuffer;
  List<String> _primaryKeys = [];
  Map<String, String> _columnDataTypes = {};
  bool _schemaLoaded = false;
  bool _isSaving = false;

  String get _tableTitle => '${widget.schema}.${widget.tableName}';

  bool get _isDirty => _stagingBuffer?.isDirty ?? false;

  bool get _editingEnabled => tableViewEditingEnabled(
        isView: widget.isView,
        isMaterializedView: widget.isMaterializedView,
        customSqlActive: _customSqlActive,
        hasPrimaryKey: _primaryKeys.isNotEmpty,
      );

  @override
  void initState() {
    super.initState();
    _connectAndLoad();
  }

  @override
  void didUpdateWidget(covariant PostgresTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database ||
        oldWidget.schema != widget.schema ||
        oldWidget.tableName != widget.tableName ||
        oldWidget.isMaterializedView != widget.isMaterializedView) {
      _customSqlActive = false;
      _customSql = null;
      _resetStaging();
      _disconnectCurrent();
      _connectAndLoad();
    }
  }

  @override
  void dispose() {
    _resetStaging();
    _disconnectCurrent(interruptIfBusy: true);
    super.dispose();
  }

  void _resetStaging() {
    _stagingBuffer?.dispose();
    _stagingBuffer = null;
    _primaryKeys = [];
    _columnDataTypes = {};
    _schemaLoaded = false;
    _isSaving = false;
  }

  void _disconnectCurrent({bool interruptIfBusy = false}) {
    if (interruptIfBusy && _loading) {
      PostgresService.instance.interrupt(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readWrite,
      );
    }
    _lease?.release();
    _lease = null;
  }

  Future<void> _connectAndLoad() async {
    _disconnectCurrent();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _columnNames = [];
      _rows = [];
      _rowsOnPage = 0;
      _totalRowCount = null;
      _offset = 0;
      _customSqlActive = false;
      _customSql = null;
      _resetStaging();
    });
    try {
      final lease = await PostgresService.instance.acquire(
        widget.connectionRow,
        database: widget.database,
        // Custom SQL + REFRESH MATERIALIZED VIEW need a read-write session.
        mode: PgSessionMode.readWrite,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      await _fetch(refreshCount: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _browseDataSql() {
    final schemaQ = quotePostgresIdentifier(widget.schema);
    final tableQ = quotePostgresIdentifier(widget.tableName);
    return 'SELECT * FROM $schemaQ.$tableQ LIMIT ${widget.limit} OFFSET $_offset';
  }

  Future<bool> _confirmDiscardIfNeeded() {
    return confirmDiscardTableEditsIfDirty(
      context: context,
      buffer: _stagingBuffer,
      tableTitle: _tableTitle,
    );
  }

  Future<void> _ensureSchema(PostgresConnection conn) async {
    if (_schemaLoaded) return;
    if (widget.isView || widget.isMaterializedView) {
      _schemaLoaded = true;
      _primaryKeys = [];
      _columnDataTypes = {};
      return;
    }
    try {
      final schema = await conn.getTableSchema(
        schema: widget.schema,
        table: widget.tableName,
      );
      _primaryKeys = List<String>.from(schema.primaryKeys);
      _columnDataTypes = columnDataTypesFromSchema(schema);
    } catch (_) {
      _primaryKeys = [];
      _columnDataTypes = {};
    }
    _schemaLoaded = true;
  }

  void _installStagingBuffer(List<String> columns, List<List<String>> rows) {
    _stagingBuffer = replaceTableViewStagingBuffer(
      previous: _stagingBuffer,
      columns: columns,
      rows: rows,
      enabled: _editingEnabled,
    );
  }

  /// [refreshCount] runs `COUNT(*)` (e.g. first load or Refresh). Pagination only runs SELECT.
  Future<void> _fetch({bool refreshCount = false}) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      if (mounted && _loading) {
        setState(() {
          _error = 'Not connected';
          _loading = false;
        });
      }
      return;
    }
    if (_customSqlActive) {
      await _fetchCustom();
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final schemaQ = quotePostgresIdentifier(widget.schema);
    final tableQ = quotePostgresIdentifier(widget.tableName);
    final countSql = 'SELECT COUNT(*) AS c FROM $schemaQ.$tableQ';
    final dataSql = _browseDataSql();
    try {
      int totalRows;
      if (refreshCount || _totalRowCount == null) {
        final countResult = await conn.execute(countSql);
        totalRows = countResult.isEmpty ? 0 : _asInt(countResult.first[0]);
      } else {
        totalRows = _totalRowCount!;
      }

      final result = await conn.execute(dataSql);
      if (!mounted) return;

      await _ensureSchema(conn);
      if (!mounted) return;

      final colNames = List<String>.generate(
        result.schema.columns.length,
        (i) => result.schema.columns[i].columnName ?? 'col_$i',
      );

      final rawRows = <List<Object?>>[
        for (final row in result)
          List<Object?>.generate(row.length, (i) => row[i]),
      ];

      final stringRows = await convertResultRowsToStringsAdaptive(rawRows);

      if (!mounted) return;
      setState(() {
        _columnNames = colNames;
        _rows = stringRows;
        _rowsOnPage = stringRows.length;
        if (refreshCount || _totalRowCount == null) {
          _totalRowCount = totalRows;
        }
        _loading = false;
        _installStagingBuffer(colNames, stringRows);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchCustom() async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      if (mounted && _loading) {
        setState(() {
          _error = 'Not connected';
          _loading = false;
        });
      }
      return;
    }
    final sql = _customSql;
    if (sql == null || sql.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await conn.execute(sql);
      if (!mounted) return;

      final colNames = List<String>.generate(
        result.schema.columns.length,
        (i) => result.schema.columns[i].columnName ?? 'col_$i',
      );

      final rawRows = <List<Object?>>[
        for (final row in result)
          List<Object?>.generate(row.length, (i) => row[i]),
      ];

      final stringRows = await convertResultRowsToStringsAdaptive(rawRows);

      if (!mounted) return;
      setState(() {
        _columnNames = colNames;
        _rows = stringRows;
        _rowsOnPage = stringRows.length;
        _totalRowCount = null;
        _loading = false;
        _installStagingBuffer(colNames, stringRows);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _onSqlRun(String sql) async {
    final trimmed = sql.trim();
    if (!isAllowedPostgresSelectQuery(trimmed)) return;
    if (!await _confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    final browse = _browseDataSql().trim();
    if (_browseSqlCompareKey(trimmed) == _browseSqlCompareKey(browse)) {
      setState(() {
        _customSqlActive = false;
        _customSql = null;
      });
      await _fetch(refreshCount: true);
    } else {
      setState(() {
        _customSqlActive = true;
        _customSql = trimmed;
      });
      await _fetchCustom();
    }
  }

  Future<void> _refreshMaterializedView() async {
    final conn = _connection;
    if (conn == null || !conn.isConnected || _loading) return;
    if (!await _confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    try {
      await conn.refreshMaterializedView(widget.schema, widget.tableName);
      if (!mounted) return;
      await _fetch(refreshCount: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _openPrivileges() {
    final conn = _connection;
    if (conn == null || !conn.isConnected) return;
    showPostgresTablePrivilegesDialog(
      context: context,
      connection: conn,
      schema: widget.schema,
      tableName: widget.tableName,
    );
  }

  void _openSqlEditor() {
    showPostgresSqlEditorDialog(
      context: context,
      initialSql: (_customSqlActive && _customSql != null)
          ? _customSql!
          : _browseDataSql(),
      browseSql: _browseDataSql(),
      onRun: (sql) => unawaited(_onSqlRun(sql)),
    );
  }

  Future<void> _exitCustomMode() async {
    if (!await _confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    setState(() {
      _customSqlActive = false;
      _customSql = null;
    });
    await _fetch(refreshCount: true);
  }

  void _goToPreviousPage() {
    if (_customSqlActive) return;
    if (_offset <= 0 || _loading || _isDirty) return;
    setState(() {
      final next = _offset - widget.limit;
      _offset = next < 0 ? 0 : next;
    });
    unawaited(_fetch());
  }

  void _goToNextPage() {
    if (_customSqlActive) return;
    if (_loading || _isDirty) return;
    final total = _totalRowCount;
    final limit = widget.limit;
    if (total != null && _offset + _rowsOnPage >= total) return;
    if (total == null && _rowsOnPage < limit) return;
    setState(() {
      _offset += limit;
    });
    unawaited(_fetch());
  }

  bool get _canGoPrevious =>
      !_customSqlActive && _offset > 0 && !_loading && !_isDirty;

  bool get _canGoNext {
    if (_customSqlActive || _loading || _isDirty) return false;
    final total = _totalRowCount;
    final limit = widget.limit;
    if (total != null) {
      return _offset + _rowsOnPage < total;
    }
    return _rowsOnPage >= limit;
  }

  String _paginationLabel() {
    if (_customSqlActive) {
      if (_rowsOnPage == 0) return '0 rows (custom SQL)';
      return '$_rowsOnPage row${_rowsOnPage == 1 ? '' : 's'} (custom SQL)';
    }
    if (_rowsOnPage == 0) {
      final t = _totalRowCount;
      if (t == null) return '0 rows';
      return '0 of $t';
    }
    final start = _offset + 1;
    final end = _offset + _rowsOnPage;
    final total = _totalRowCount;
    if (total != null) {
      return '$start–$end of $total';
    }
    return '$start–$end';
  }

  String? _statusLine() {
    final reason = tableViewEditDisabledReason(
      isView: widget.isView,
      isMaterializedView: widget.isMaterializedView,
      customSqlActive: _customSqlActive,
      hasPrimaryKey: _primaryKeys.isNotEmpty,
      schemaLoaded: _schemaLoaded,
    );
    final pag = _paginationLabel();
    if (reason != null) return '$pag · $reason';
    return pag;
  }

  Future<void> _onRefresh() async {
    if (!await _confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    if (_customSqlActive) {
      await _fetchCustom();
    } else {
      await _fetch(refreshCount: true);
    }
  }

  Future<void> _onNavigateHome() async {
    final home = widget.onNavigateHome;
    if (home == null) return;
    if (!await _confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    home();
  }

  Future<void> _applyStagedChanges() async {
    final buffer = _stagingBuffer;
    if (buffer == null || !buffer.isDirty || _isSaving) return;
    setState(() => _isSaving = true);
    final outcome = await applyTableViewStagedChanges(
      context: context,
      buffer: buffer,
      dialect: SqlDialect.postgres,
      tableName: widget.tableName,
      schema: widget.schema,
      primaryKeys: _primaryKeys,
      columnDataTypes: _columnDataTypes.isEmpty ? null : _columnDataTypes,
      execute: (plan) async {
        final conn = _connection;
        if (conn == null || !conn.isConnected) {
          throw StateError('Could not connect to PostgreSQL.');
        }
        await conn.execute(plan.toTransactionSql());
      },
    );
    if (!mounted) return;
    if (outcome.isApplied) {
      final newRows = buffer.effectiveRows;
      buffer.dispose();
      setState(() {
        _rows = newRows;
        _rowsOnPage = newRows.length;
        _stagingBuffer = replaceTableViewStagingBuffer(
          previous: null,
          columns: _columnNames,
          rows: newRows,
          enabled: _editingEnabled,
        );
        _isSaving = false;
      });
      showAppToast(
        context: context,
        message: '${outcome.statementCount} change(s) saved',
        variant: AppToastVariant.success,
      );
      return;
    }
    setState(() => _isSaving = false);
    if (outcome.isFailed && outcome.error != null) {
      await showTableViewSaveFailedDialog(
        context: context,
        error: outcome.error!,
      );
    }
  }

  material.Widget _buildToolbar() {
    PostgresTableToolbar toolbar() => PostgresTableToolbar(
          title:
              '$_tableTitle${widget.isMaterializedView ? ' (materialized view)' : widget.isView ? ' (view)' : ''}',
          paginationLabel: _paginationLabel(),
          tableIcon: widget.isMaterializedView
              ? material.Icons.dynamic_feed_rounded
              : widget.isView
                  ? material.Icons.view_agenda_rounded
                  : material.Icons.table_chart_rounded,
          customSqlActive: _customSqlActive,
          isMaterializedView: widget.isMaterializedView,
          loading: _loading,
          canGoPrevious: _canGoPrevious,
          canGoNext: _canGoNext,
          onNavigateHome: widget.onNavigateHome == null
              ? null
              : () => unawaited(_onNavigateHome()),
          onOpenSql: _openSqlEditor,
          onOpenPrivileges: _openPrivileges,
          onRefreshMaterializedView: () =>
              unawaited(_refreshMaterializedView()),
          onExitCustomMode: () => unawaited(_exitCustomMode()),
          onGoPrevious: _goToPreviousPage,
          onGoNext: _goToNextPage,
          onRefresh: () => unawaited(_onRefresh()),
          pendingActions: _stagingBuffer == null
              ? null
              : TableBrowserPendingActions(
                  buffer: _stagingBuffer!,
                  onSave: () => unawaited(_applyStagedChanges()),
                  isSaving: _isSaving,
                ),
        );
    final buffer = _stagingBuffer;
    if (buffer == null) return toolbar();
    return ListenableBuilder(
      listenable: buffer,
      builder: (context, _) => toolbar(),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return material.CallbackShortcuts(
      bindings: {
        const material.SingleActivator(LogicalKeyboardKey.f5): () {
          if (!_loading) unawaited(_onRefresh());
        },
      },
      child: material.Focus(
        autofocus: true,
        child: material.Container(
          color: cs.background,
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            children: [
              _buildToolbar(),
              material.Expanded(
                child: ResultsTab(
                  columns: _columnNames,
                  rows: _rows,
                  errorMessage: _error,
                  isLoading: _loading,
                  statusLine: _statusLine(),
                  showExportToolbar: true,
                  stagingBuffer: _stagingBuffer,
                  columnDataTypes:
                      _columnDataTypes.isEmpty ? null : _columnDataTypes,
                  onApplyChanges:
                      _stagingBuffer != null ? _applyStagedChanges : null,
                  isSaving: _isSaving,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ignores trailing semicolons and whitespace so Run matches the browse query.
  static String _browseSqlCompareKey(String sql) {
    var s = sql.trim();
    while (s.endsWith(';')) {
      s = s.substring(0, s.length - 1).trimRight();
    }
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }
}
