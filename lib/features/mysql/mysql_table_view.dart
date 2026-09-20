import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:mysql_client/mysql_client.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/mysql_result_cells.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/database/sql_limit.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/mysql/mysql_sql_editor_dialog.dart';
import 'package:querya_desktop/features/mysql/mysql_table_utils.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _defaultLimit = 200;

class MysqlTableView extends material.StatefulWidget {
  const MysqlTableView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.tableName,
    this.isView = false,
    this.limit = _defaultLimit,
    this.onNavigateHome,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String tableName;
  final bool isView;
  final int limit;
  final VoidCallback? onNavigateHome;

  /// Title-bar session lock: no staging / Save / `tableWrite` acquire.
  final bool isReadOnly;

  @override
  material.State<MysqlTableView> createState() => _MysqlTableViewState();
}

class _MysqlTableViewState extends material.State<MysqlTableView> {
  MysqlLease? _lease;
  MysqlConnection? get _connection => _lease?.connection;

  bool _loading = true;
  String? _error;

  List<String> _columnNames = [];
  List<List<String>> _rows = [];
  int _rowsOnPage = 0;
  int? _totalRowCount;
  int _offset = 0;
  bool _customSqlActive = false;
  String? _customSql;

  DataGridStagingBuffer? _stagingBuffer;
  List<String> _primaryKeys = [];
  Map<String, String> _columnDataTypes = {};
  Map<String, TableColumnMeta> _columnMeta = {};
  bool _schemaLoaded = false;
  bool _isSaving = false;

  String get _tableTitle => '${widget.database}.${widget.tableName}';

  bool get _isDirty => _stagingBuffer?.isDirty ?? false;

  bool get _editingEnabled => tableViewEditingEnabled(
        isView: widget.isView,
        customSqlActive: _customSqlActive,
        hasPrimaryKey: _primaryKeys.isNotEmpty,
        readOnly: widget.isReadOnly,
      );

  String _qualifiedFrom() {
    final d = MysqlConnection.quoteIdentifier(widget.database);
    final t = MysqlConnection.quoteIdentifier(widget.tableName);
    return '$d.$t';
  }

  String _browseDataSql() {
    return mysqlBrowseDataSql(
      qualifiedFrom: _qualifiedFrom(),
      primaryKeys: _primaryKeys,
      limit: widget.limit,
      offset: _offset,
    );
  }

  @override
  void initState() {
    super.initState();
    _connectAndLoad();
  }

  @override
  void didUpdateWidget(covariant MysqlTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database ||
        oldWidget.tableName != widget.tableName ||
        oldWidget.isView != widget.isView) {
      _customSqlActive = false;
      _customSql = null;
      _resetStaging();
      _disconnectCurrent(interruptIfBusy: true);
      _connectAndLoad();
    } else if (oldWidget.isReadOnly != widget.isReadOnly) {
      _syncStagingToReadOnly();
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
    _columnMeta = {};
    _schemaLoaded = false;
    _isSaving = false;
  }

  void _syncStagingToReadOnly() {
    if (widget.isReadOnly) {
      _stagingBuffer?.dispose();
      _stagingBuffer = null;
    } else if (_columnNames.isNotEmpty) {
      _stagingBuffer = replaceTableViewStagingBuffer(
        previous: _stagingBuffer,
        columns: _columnNames,
        rows: _rows,
        enabled: _editingEnabled,
      );
    }
    if (mounted) setState(() {});
  }

  void _disconnectCurrent({bool interruptIfBusy = false}) {
    if (interruptIfBusy && _loading) {
      MysqlService.instance.interrupt(
        widget.connectionRow,
        database: widget.database,
        mode: MysqlSessionMode.readOnly,
      );
    }
    if (interruptIfBusy && _isSaving) {
      MysqlService.instance.interrupt(
        widget.connectionRow,
        database: widget.database,
        mode: MysqlSessionMode.tableWrite,
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
      final lease = await MysqlService.instance.acquire(
        widget.connectionRow,
        database: widget.database,
        mode: MysqlSessionMode.readOnly,
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

  List<String> _resultColumns(IResultSet rs) {
    return rs.cols.map((c) => c.name.isNotEmpty ? c.name : 'col').toList();
  }

  Future<List<List<String>>> _resultRowsAsync(IResultSet rs) async {
    final colList = rs.cols.toList();
    final out = <List<String>>[];
    var n = 0;
    for (final row in rs.rows) {
      out.add(
        List.generate(
          row.numOfColumns,
          (i) {
            final col = i < colList.length ? colList[i] : null;
            return mysqlResultCellToDisplayString(
              row.colAt(i),
              column: col,
              schemaDataType: col == null ? null : _columnDataTypes[col.name],
            );
          },
        ),
      );
      n++;
      if (n % kResultStringConvertYieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return out;
  }

  Future<T> _withTableWrite<T>(
    Future<T> Function(MysqlConnection conn) fn,
  ) async {
    if (widget.isReadOnly) {
      throw StateError('MySQL session is read-only');
    }
    final lease = await MysqlService.instance.acquire(
      widget.connectionRow,
      database: widget.database,
      mode: MysqlSessionMode.tableWrite,
    );
    try {
      return await fn(lease.connection);
    } finally {
      lease.release();
    }
  }

  Future<bool> _confirmDiscardIfNeeded() {
    return confirmDiscardTableEditsIfDirty(
      context: context,
      buffer: _stagingBuffer,
      tableTitle: _tableTitle,
    );
  }

  Future<void> _ensureSchema(MysqlConnection conn) async {
    if (_schemaLoaded) return;
    if (widget.isView) {
      _schemaLoaded = true;
      _primaryKeys = [];
      _columnDataTypes = {};
      _columnMeta = {};
      return;
    }
    try {
      final schema = await conn.getTableSchema(
        database: widget.database,
        table: widget.tableName,
      );
      _primaryKeys = List<String>.from(schema.primaryKeys);
      _columnDataTypes = columnDataTypesFromSchema(schema);
      _columnMeta = columnMetaFromSchema(schema);
    } catch (_) {
      _primaryKeys = [];
      _columnDataTypes = {};
      _columnMeta = {};
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
    try {
      await _ensureSchema(conn);
      if (!mounted) return;

      int? totalRows = _totalRowCount;
      if (refreshCount || totalRows == null) {
        try {
          totalRows = await conn.estimateTableRows(
            database: widget.database,
            table: widget.tableName,
          );
        } catch (_) {
          totalRows = null;
        }
      }

      final dataSql = _browseDataSql();
      final result = await conn.execute(dataSql);
      if (!mounted) return;

      final colNames = _resultColumns(result);
      final stringRows = await _resultRowsAsync(result);

      if (!mounted) return;
      final shown = stringRows.length;
      if (totalRows != null && shown > 0 && totalRows < _offset + shown) {
        totalRows = null;
      }
      setState(() {
        _columnNames = colNames;
        _rows = stringRows;
        _rowsOnPage = shown;
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
      final result = await conn.execute(
        injectSqlLimit(sql, kDefaultSqlResultMaxRows),
      );
      if (!mounted) return;
      final stringRows = await _resultRowsAsync(result);
      if (!mounted) return;
      setState(() {
        _columnNames = _resultColumns(result);
        _rows = stringRows;
        _rowsOnPage = _rows.length;
        _totalRowCount = null;
        _loading = false;
        _installStagingBuffer(_columnNames, stringRows);
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
    if (!isAllowedMysqlSelectQuery(trimmed)) return;
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

  void _openSqlEditor() {
    showMysqlSqlEditorDialog(
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
      customSqlActive: _customSqlActive,
      hasPrimaryKey: _primaryKeys.isNotEmpty,
      schemaLoaded: _schemaLoaded,
      readOnly: widget.isReadOnly,
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
    if (widget.isReadOnly) return;
    final buffer = _stagingBuffer;
    if (buffer == null || !buffer.isDirty || _isSaving) return;
    setState(() => _isSaving = true);
    final outcome = await applyTableViewStagedChanges(
      context: context,
      buffer: buffer,
      dialect: SqlDialect.mysql,
      tableName: widget.tableName,
      schema: widget.database,
      primaryKeys: _primaryKeys,
      columnDataTypes: _columnDataTypes.isEmpty ? null : _columnDataTypes,
      columnMeta: _columnMeta.isEmpty ? null : _columnMeta,
      execute: (plan) async {
        await _withTableWrite((conn) async {
          if (!conn.isConnected) {
            throw StateError('Could not connect to MySQL.');
          }
          await conn.runInTransaction(() async {
            for (final stmt in plan.statements) {
              final rs = await conn.execute(stmt.sql);
              expectDmlMatchedRows(rs.affectedRows.toInt());
            }
          });
        });
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

  material.Widget _buildChromeRow(ColorScheme cs) {
    final title = '$_tableTitle${widget.isView ? ' (view)' : ''}';
    return material.Container(
      height: 48,
      padding: const material.EdgeInsets.symmetric(horizontal: 12),
      decoration: material.BoxDecoration(
        color: cs.muted.withValues(alpha: 0.35),
        border: material.Border(
          bottom: material.BorderSide(
            color: cs.border.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: material.Row(
        children: [
          if (widget.onNavigateHome != null) ...[
            material.Tooltip(
              message: 'Return to server overview',
              child: OutlineButton(
                size: ButtonSize.small,
                onPressed: () => unawaited(_onNavigateHome()),
                leading: const material.Icon(
                  material.Icons.dns_outlined,
                  size: 14,
                ),
                child: const Text('Server'),
              ),
            ),
            const Gap(10),
          ],
          material.Icon(
            widget.isView
                ? material.Icons.view_agenda_rounded
                : material.Icons.table_chart_rounded,
            size: 20,
            color: cs.primary,
          ),
          const Gap(8),
          material.Expanded(
            child: material.Text(
              title,
              overflow: material.TextOverflow.ellipsis,
              maxLines: 1,
              style: material.TextStyle(
                fontSize: 13,
                fontWeight: material.FontWeight.w600,
                color: cs.foreground,
              ),
            ),
          ),
          material.Expanded(
            flex: 2,
            child: material.LayoutBuilder(
              builder: (context, constraints) {
                return material.SingleChildScrollView(
                  scrollDirection: material.Axis.horizontal,
                  child: material.ConstrainedBox(
                    constraints: material.BoxConstraints(
                      minWidth: constraints.maxWidth,
                    ),
                    child: material.Row(
                      mainAxisAlignment: material.MainAxisAlignment.end,
                      mainAxisSize: material.MainAxisSize.min,
                      children: [
                        material.Container(
                          padding: const material.EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: material.BoxDecoration(
                            color: cs.muted.withValues(alpha: 0.4),
                            borderRadius: material.BorderRadius.circular(4),
                          ),
                          child: material.Text(
                            _paginationLabel(),
                            style: material.TextStyle(
                              fontSize: 11,
                              color: cs.mutedForeground,
                            ),
                          ),
                        ),
                        const Gap(6),
                        if (_stagingBuffer != null)
                          TableBrowserPendingActions(
                            buffer: _stagingBuffer!,
                            onSave: () => unawaited(_applyStagedChanges()),
                            isSaving: _isSaving,
                          ),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: _openSqlEditor,
                          leading: const material.Icon(
                            material.Icons.code_rounded,
                            size: 15,
                          ),
                          child: const Text('SQL'),
                        ),
                        if (_customSqlActive) ...[
                          const Gap(4),
                          OutlineButton(
                            size: ButtonSize.small,
                            onPressed: () => unawaited(_exitCustomMode()),
                            leading: const material.Icon(
                              material.Icons.table_chart_rounded,
                              size: 15,
                            ),
                            child: const Text('Browse'),
                          ),
                        ],
                        const Gap(4),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: (!_canGoPrevious || _loading)
                              ? null
                              : _goToPreviousPage,
                          leading: const material.Icon(
                            material.Icons.chevron_left_rounded,
                            size: 16,
                          ),
                          child: const Text('Prev'),
                        ),
                        const Gap(4),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed:
                              (!_canGoNext || _loading) ? null : _goToNextPage,
                          leading: const material.Icon(
                            material.Icons.chevron_right_rounded,
                            size: 16,
                          ),
                          child: const Text('Next'),
                        ),
                        const Gap(8),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed:
                              _loading ? null : () => unawaited(_onRefresh()),
                          leading: const material.Icon(
                            material.Icons.refresh_rounded,
                            size: 14,
                          ),
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buffer = _stagingBuffer;

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
              if (buffer == null)
                _buildChromeRow(cs)
              else
                ListenableBuilder(
                  listenable: buffer,
                  builder: (context, _) => _buildChromeRow(cs),
                ),
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

  static String _browseSqlCompareKey(String sql) {
    var s = sql.trim();
    while (s.endsWith(';')) {
      s = s.substring(0, s.length - 1).trimRight();
    }
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }
}
