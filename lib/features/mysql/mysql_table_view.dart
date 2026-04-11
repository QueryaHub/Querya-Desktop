import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:mysql_client/mysql_client.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/mysql/mysql_sql_editor_dialog.dart';
import 'package:querya_desktop/features/mysql/mysql_table_utils.dart';
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
  });

  final ConnectionRow connectionRow;
  final String database;
  final String tableName;
  final bool isView;
  final int limit;

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

  final _verticalController = material.ScrollController();
  final _horizontalController = material.ScrollController();

  String _qualifiedFrom() {
    final d = MysqlConnection.quoteIdentifier(widget.database);
    final t = MysqlConnection.quoteIdentifier(widget.tableName);
    return '$d.$t';
  }

  String _browseDataSql() {
    return 'SELECT * FROM ${_qualifiedFrom()} LIMIT ${widget.limit} OFFSET $_offset';
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
      _disconnectCurrent(interruptIfBusy: true);
      _connectAndLoad();
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    _disconnectCurrent(interruptIfBusy: true);
    super.dispose();
  }

  void _disconnectCurrent({bool interruptIfBusy = false}) {
    if (interruptIfBusy && _loading) {
      MysqlService.instance.interrupt(
        widget.connectionRow,
        database: widget.database,
        mode: MysqlSessionMode.readWrite,
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
    });
    try {
      final lease = await MysqlService.instance.acquire(
        widget.connectionRow,
        database: widget.database,
        mode: MysqlSessionMode.readWrite,
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

  static int _asInt(String? v) {
    if (v == null) return 0;
    return int.tryParse(v) ?? 0;
  }

  List<String> _resultColumns(IResultSet rs) {
    return rs.cols.map((c) => c.name.isNotEmpty ? c.name : 'col').toList();
  }

  List<List<String>> _resultRows(IResultSet rs) {
    final out = <List<String>>[];
    for (final row in rs.rows) {
      out.add(
        List.generate(
          row.numOfColumns,
          (i) => row.colAt(i) ?? 'NULL',
        ),
      );
    }
    return out;
  }

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
    final from = _qualifiedFrom();
    final countSql = 'SELECT COUNT(*) AS c FROM $from';
    final dataSql = _browseDataSql();
    try {
      int totalRows;
      if (refreshCount || _totalRowCount == null) {
        final countRs = await conn.execute(countSql);
        totalRows = countRs.rows.isEmpty
            ? 0
            : _asInt(countRs.rows.first.colAt(0));
      } else {
        totalRows = _totalRowCount!;
      }

      final result = await conn.execute(dataSql);
      if (!mounted) return;

      final colNames = _resultColumns(result);
      final stringRows = _resultRows(result);

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
      setState(() {
        _columnNames = _resultColumns(result);
        _rows = _resultRows(result);
        _rowsOnPage = _rows.length;
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
    if (!isAllowedMysqlSelectQuery(trimmed)) return;
    final browse = _browseDataSql().trim();
    if (trimmed == browse) {
      setState(() {
        _customSqlActive = false;
        _customSql = null;
      });
      unawaited(_fetch(refreshCount: true));
    } else {
      setState(() {
        _customSqlActive = true;
        _customSql = trimmed;
      });
      unawaited(_fetchCustom());
    }
  }

  void _openSqlEditor() {
    showMysqlSqlEditorDialog(
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
    unawaited(_fetch(refreshCount: true));
  }

  void _goToPreviousPage() {
    if (_customSqlActive) return;
    if (_offset <= 0 || _loading) return;
    setState(() {
      final next = _offset - widget.limit;
      _offset = next < 0 ? 0 : next;
    });
    unawaited(_fetch());
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
    unawaited(_fetch());
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
                      unawaited(_fetchCustom());
                    } else {
                      unawaited(_fetch(refreshCount: true));
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
    final title =
        '${widget.database}.${widget.tableName}${widget.isView ? ' (view)' : ''}';

    return material.Container(
      color: cs.background,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Container(
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
                    style: material.TextStyle(
                      fontSize: 13,
                      fontWeight: material.FontWeight.w600,
                      color: cs.foreground,
                    ),
                  ),
                ),
                material.Text(
                  _paginationLabel(),
                  style: material.TextStyle(
                    fontSize: 11,
                    color: cs.mutedForeground,
                  ),
                ),
                const Gap(8),
                OutlineButton(
                  onPressed: _loading
                      ? null
                      : () {
                          if (_customSqlActive) {
                            unawaited(_fetchCustom());
                          } else {
                            unawaited(_fetch(refreshCount: true));
                          }
                        },
                  child: const Text('Refresh'),
                ),
                const Gap(6),
                OutlineButton(
                  onPressed: _openSqlEditor,
                  child: const Text('SQL'),
                ),
                if (_customSqlActive) ...[
                  const Gap(6),
                  OutlineButton(
                    onPressed: _exitCustomMode,
                    child: const Text('Browse'),
                  ),
                ],
                const Gap(6),
                GhostButton(
                  onPressed: (!_canGoPrevious || _loading)
                      ? null
                      : _goToPreviousPage,
                  child: const Icon(material.Icons.chevron_left_rounded, size: 20),
                ),
                GhostButton(
                  onPressed: (!_canGoNext || _loading) ? null : _goToNextPage,
                  child: const Icon(material.Icons.chevron_right_rounded, size: 20),
                ),
              ],
            ),
          ),
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
                                        _rowNumberCell(cs, '$displayRowNum'),
                                        for (var c = 0; c < colCount; c++)
                                          _dataCell(
                                              cs,
                                              row.length > c ? row[c] : ''),
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
