import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_editor_dialog.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_privileges_dialog.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_utils.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _defaultLimit = 200;

class PostgresTableView extends material.StatefulWidget {
  const PostgresTableView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.schema,
    required this.tableName,
    this.isView = false,
    this.isMaterializedView = false,
    this.limit = _defaultLimit,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String schema;
  final String tableName;
  final bool isView;
  /// When true, toolbar offers REFRESH MATERIALIZED VIEW and matview label.
  final bool isMaterializedView;
  final int limit;

  @override
  material.State<PostgresTableView> createState() =>
      _PostgresTableViewState();
}

class _PostgresTableViewState extends material.State<PostgresTableView> {
  PostgresConnection? _connection;
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

  final _verticalController = material.ScrollController();
  final _horizontalController = material.ScrollController();

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
      _disconnectCurrent();
      _connectAndLoad();
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    _disconnectCurrent();
    super.dispose();
  }

  void _disconnectCurrent() {
    final conn = _connection;
    _connection = null;
    conn?.disconnect();
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
    });
    try {
      final c = widget.connectionRow;
      final conn = PostgresConnection(
        id: c.id ?? 0,
        name: c.name,
        host: c.host ?? 'localhost',
        port: c.port ?? 5432,
        username: c.username,
        password: c.password,
        database: widget.database,
        useSSL: c.useSSL,
      );
      await conn.connect();
      if (!mounted) {
        conn.disconnect();
        return;
      }
      _connection = conn;
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

  /// [refreshCount] runs `COUNT(*)` (e.g. first load or Refresh). Pagination only runs SELECT.
  Future<void> _fetch({bool refreshCount = false}) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) return;
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
        totalRows = countResult.isEmpty
            ? 0
            : _asInt(countResult.first[0]);
      } else {
        totalRows = _totalRowCount!;
      }

      final result = await conn.execute(dataSql);
      if (!mounted) return;

      final colNames = List<String>.generate(
        result.schema.columns.length,
        (i) => result.schema.columns[i].columnName ?? 'col_$i',
      );

      final rawRows = result.map((row) {
        return List<dynamic>.generate(row.length, (i) => row[i]);
      }).toList();

      final stringRows = await compute(convertResultRowsToStrings, rawRows);

      if (!mounted) return;
      setState(() {
        _columnNames = colNames;
        _rows = stringRows;
        _rowsOnPage = stringRows.length;
        if (refreshCount || _totalRowCount == null) {
          _totalRowCount = totalRows;
        }
        _loading = false;
      });
      if (_verticalController.hasClients) {
        _verticalController.jumpTo(0);
      }
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
    if (conn == null || !conn.isConnected) return;
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

      final rawRows = result.map((row) {
        return List<dynamic>.generate(row.length, (i) => row[i]);
      }).toList();

      final stringRows = await compute(convertResultRowsToStrings, rawRows);

      if (!mounted) return;
      setState(() {
        _columnNames = colNames;
        _rows = stringRows;
        _rowsOnPage = stringRows.length;
        _totalRowCount = null;
        _loading = false;
      });
      if (_verticalController.hasClients) {
        _verticalController.jumpTo(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _onSqlRun(String sql) {
    final trimmed = sql.trim();
    if (!isAllowedPostgresSelectQuery(trimmed)) return;
    final browse = _browseDataSql().trim();
    if (trimmed == browse) {
      setState(() {
        _customSqlActive = false;
        _customSql = null;
      });
      _fetch(refreshCount: true);
    } else {
      setState(() {
        _customSqlActive = true;
        _customSql = trimmed;
      });
      _fetchCustom();
    }
  }

  Future<void> _refreshMaterializedView() async {
    final conn = _connection;
    if (conn == null || !conn.isConnected || _loading) return;
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
      onRun: _onSqlRun,
    );
  }

  void _exitCustomMode() {
    setState(() {
      _customSqlActive = false;
      _customSql = null;
    });
    _fetch(refreshCount: true);
  }

  void _goToPreviousPage() {
    if (_customSqlActive) return;
    if (_offset <= 0 || _loading) return;
    setState(() {
      final next = _offset - widget.limit;
      _offset = next < 0 ? 0 : next;
    });
    _fetch();
  }

  void _goToNextPage() {
    if (_customSqlActive) return;
    if (_loading) return;
    final total = _totalRowCount;
    final limit = widget.limit;
    if (total != null && _offset + _rowsOnPage >= total) return;
    if (total == null && _rowsOnPage < limit) return;
    setState(() {
      _offset += limit;
    });
    _fetch();
  }

  bool get _canGoPrevious =>
      !_customSqlActive && _offset > 0 && !_loading;

  bool get _canGoNext {
    if (_customSqlActive) return false;
    if (_loading) return false;
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

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return material.Container(
        color: cs.background,
        child: material.Center(
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              const material.SizedBox(
                width: 28,
                height: 28,
                child: material.CircularProgressIndicator(strokeWidth: 2),
              ),
              const Gap(12),
              const Text('Loading data...').muted().small(),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return material.Container(
        color: cs.background,
        child: material.Center(
          child: material.Padding(
            padding: const material.EdgeInsets.all(32),
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Icon(material.Icons.error_outline_rounded,
                    size: 48, color: cs.destructive),
                const Gap(16),
                const Text('Query Error').large().semiBold(),
                const Gap(8),
                material.SelectableText(_error!,
                    style: material.TextStyle(
                        color: cs.mutedForeground, fontSize: 13)),
                const Gap(24),
                OutlineButton(
                  onPressed: () {
                    if (_customSqlActive) {
                      _fetchCustom();
                    } else {
                      _fetch(refreshCount: true);
                    }
                  },
                  leading: const material.Icon(material.Icons.refresh_rounded,
                      size: 18),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_columnNames.isEmpty) {
      return material.Container(color: cs.background);
    }

    const double rowHeight = 36;
    const double headerHeight = 40;
    final colCount = _columnNames.length;

    return material.Container(
      color: cs.background,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          // Toolbar
          material.Container(
            padding: const material.EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: material.BoxDecoration(
              color: cs.card,
              border: material.Border(
                bottom: material.BorderSide(
                    color: cs.border.withValues(alpha: 0.5)),
              ),
            ),
            child: material.Row(
              children: [
                material.Icon(
                  widget.isMaterializedView
                      ? material.Icons.dynamic_feed_rounded
                      : widget.isView
                          ? material.Icons.view_agenda_rounded
                          : material.Icons.table_chart_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const Gap(8),
                material.Expanded(
                  child: material.Text(
                    '${widget.schema}.${widget.tableName}'
                        '${widget.isMaterializedView ? ' (materialized view)' : widget.isView ? ' (view)' : ''}',
                    style: material.TextStyle(
                      fontSize: 13,
                      fontWeight: material.FontWeight.w600,
                      color: cs.foreground,
                    ),
                    overflow: material.TextOverflow.ellipsis,
                  ),
                ),
                material.Container(
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: material.BoxDecoration(
                    color: cs.muted.withValues(alpha: 0.4),
                    borderRadius: material.BorderRadius.circular(4),
                  ),
                  child: material.Text(
                    _paginationLabel(),
                    style: material.TextStyle(
                        fontSize: 11, color: cs.mutedForeground),
                  ),
                ),
                const Gap(6),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _openSqlEditor,
                  leading: const material.Icon(
                    material.Icons.code_rounded,
                    size: 16,
                  ),
                  child: const Text('SQL'),
                ),
                const Gap(4),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _openPrivileges,
                  leading: const material.Icon(
                    material.Icons.admin_panel_settings_rounded,
                    size: 15,
                  ),
                  child: const Text('Privileges'),
                ),
                if (widget.isMaterializedView && !_customSqlActive) ...[
                  const Gap(4),
                  OutlineButton(
                    size: ButtonSize.small,
                    onPressed: _loading ? null : _refreshMaterializedView,
                    leading: const material.Icon(
                      material.Icons.sync_rounded,
                      size: 15,
                    ),
                    child: const Text('Refresh MV'),
                  ),
                ],
                if (_customSqlActive) ...[
                  const Gap(4),
                  OutlineButton(
                    size: ButtonSize.small,
                    onPressed: _loading ? null : _exitCustomMode,
                    leading: const material.Icon(
                      material.Icons.table_chart_rounded,
                      size: 16,
                    ),
                    child: const Text('Table'),
                  ),
                ],
                const Gap(4),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _canGoPrevious ? _goToPreviousPage : null,
                  leading: const material.Icon(
                      material.Icons.chevron_left_rounded,
                      size: 16),
                  child: const Text('Back'),
                ),
                const Gap(4),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _canGoNext ? _goToNextPage : null,
                  leading: const material.Icon(
                      material.Icons.chevron_right_rounded,
                      size: 16),
                  child: const Text('Next'),
                ),
                const Gap(8),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _loading
                      ? null
                      : () {
                          if (_customSqlActive) {
                            _fetchCustom();
                          } else {
                            _fetch(refreshCount: true);
                          }
                        },
                  leading: const material.Icon(
                      material.Icons.refresh_rounded,
                      size: 14),
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
          // Table grid
          material.Expanded(
            child: material.LayoutBuilder(
              builder: (context, constraints) {
                return material.Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: true,
                  notificationPredicate: (_) => true,
                  child: material.SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: material.Axis.horizontal,
                    child: material.SizedBox(
                      width: _calcTableWidth(colCount, constraints.maxWidth),
                      child: material.Column(
                        children: [
                          // Header
                          material.Container(
                            height: headerHeight,
                            decoration: material.BoxDecoration(
                              color: cs.muted.withValues(alpha: 0.35),
                              border: material.Border(
                                bottom: material.BorderSide(
                                    color: cs.border.withValues(alpha: 0.5)),
                              ),
                            ),
                            child: material.Row(
                              children: [
                                _rowNumberCell(cs, '#', isHeader: true),
                                for (var i = 0; i < colCount; i++)
                                  _headerCell(cs, _columnNames[i]),
                              ],
                            ),
                          ),
                          // Data rows via ListView.builder for virtualization
                          material.Expanded(
                            child: material.Scrollbar(
                              controller: _verticalController,
                              thumbVisibility: true,
                              child: material.ListView.builder(
                                controller: _verticalController,
                                itemCount: _rowsOnPage,
                                itemExtent: rowHeight,
                                itemBuilder: (context, rowIdx) {
                                  final row = _rows[rowIdx];
                                  final isEven = rowIdx % 2 == 0;
                                  final displayRowNum = _customSqlActive
                                      ? rowIdx + 1
                                      : _offset + rowIdx + 1;
                                  return material.Container(
                                    height: rowHeight,
                                    decoration: material.BoxDecoration(
                                      color: isEven
                                          ? material.Colors.transparent
                                          : cs.muted.withValues(alpha: 0.12),
                                      border: material.Border(
                                        bottom: material.BorderSide(
                                          color:
                                              cs.border.withValues(alpha: 0.15),
                                        ),
                                      ),
                                    ),
                                    child: material.Row(
                                      children: [
                                        _rowNumberCell(cs,
                                            '$displayRowNum'),
                                        for (var c = 0;
                                            c < colCount;
                                            c++)
                                          _dataCell(
                                              cs,
                                              row.length > c
                                                  ? row[c]
                                                  : ''),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
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

  double _calcTableWidth(int colCount, double availableWidth) {
    const double rowNumWidth = 52;
    const double minColWidth = 150;
    final calculated = rowNumWidth + colCount * minColWidth;
    return calculated > availableWidth ? calculated : availableWidth;
  }

  material.Widget _rowNumberCell(ColorScheme cs, String text,
      {bool isHeader = false}) {
    return material.Container(
      width: 52,
      padding: const material.EdgeInsets.symmetric(horizontal: 8),
      alignment: material.Alignment.centerRight,
      decoration: material.BoxDecoration(
        border: material.Border(
          right: material.BorderSide(color: cs.border.withValues(alpha: 0.3)),
        ),
      ),
      child: material.Text(
        text,
        style: material.TextStyle(
          fontSize: 11,
          fontWeight:
              isHeader ? material.FontWeight.w600 : material.FontWeight.normal,
          color: cs.mutedForeground.withValues(alpha: 0.7),
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  material.Widget _headerCell(ColorScheme cs, String name) {
    return material.Expanded(
      child: material.Container(
        padding: const material.EdgeInsets.symmetric(horizontal: 10),
        alignment: material.Alignment.centerLeft,
        child: material.Text(
          name,
          style: material.TextStyle(
            fontSize: 12,
            fontWeight: material.FontWeight.w600,
            color: cs.foreground,
          ),
          overflow: material.TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }

  material.Widget _dataCell(ColorScheme cs, String value) {
    final isNull = value == 'NULL';
    return material.Expanded(
      child: material.Container(
        padding: const material.EdgeInsets.symmetric(horizontal: 10),
        alignment: material.Alignment.centerLeft,
        child: material.Text(
          value,
          style: material.TextStyle(
            fontSize: 12,
            color: isNull
                ? cs.mutedForeground.withValues(alpha: 0.5)
                : cs.foreground,
            fontStyle:
                isNull ? material.FontStyle.italic : material.FontStyle.normal,
          ),
          overflow: material.TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}
