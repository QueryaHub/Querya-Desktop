import 'dart:async' show unawaited;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/sql_editor_chrome.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _defaultLimit = 200;

class SqliteTableView extends material.StatefulWidget {
  const SqliteTableView({
    super.key,
    required this.connectionRow,
    required this.tableName,
    this.isView = false,
    this.limit = _defaultLimit,
    this.onNavigateHome,
  });

  final ConnectionRow connectionRow;
  final String tableName;
  final bool isView;
  final int limit;
  final VoidCallback? onNavigateHome;

  @override
  material.State<SqliteTableView> createState() => _SqliteTableViewState();
}

class _SqliteTableViewState extends material.State<SqliteTableView> {
  SqliteLease? _lease;
  SqliteConnection? get _connection => _lease?.connection;

  bool _loading = true;
  String? _error;

  List<String> _columnNames = [];
  List<List<String>> _rows = [];
  int _rowsOnPage = 0;
  int? _totalRowCount;
  int _offset = 0;
  String? _sortColumn;
  bool _sortAscending = true;

  final _verticalController = material.ScrollController();
  final _horizontalController = material.ScrollController();

  String _qualifiedFrom() {
    return SqliteConnection.quoteIdentifier(widget.tableName);
  }

  String _browseDataSql() {
    final orderBy = _sortColumn != null
        ? ' ORDER BY ${SqliteConnection.quoteIdentifier(_sortColumn!)} ${_sortAscending ? "ASC" : "DESC"}'
        : '';
    return 'SELECT * FROM ${_qualifiedFrom()}$orderBy LIMIT ${widget.limit} OFFSET $_offset';
  }

  void _toggleSort(String columnName) {
    if (_loading) return;
    setState(() {
      if (_sortColumn == columnName) {
        if (_sortAscending) {
          _sortAscending = false;
        } else {
          _sortColumn = null;
          _sortAscending = true;
        }
      } else {
        _sortColumn = columnName;
        _sortAscending = true;
      }
      _offset = 0;
    });
    unawaited(_fetch());
  }

  @override
  void initState() {
    super.initState();
    _connectAndLoad();
  }

  @override
  void didUpdateWidget(covariant SqliteTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.tableName != widget.tableName ||
        oldWidget.isView != widget.isView) {
      _sortColumn = null;
      _sortAscending = true;
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
    });
    try {
      final lease = await SqliteService.instance.acquire(
        widget.connectionRow,
        mode: SqliteSessionMode.readOnly,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      await _fetch(refreshCount: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (refreshCount) {
        try {
          final countRs =
              await conn.execute('SELECT COUNT(*) FROM ${_qualifiedFrom()}');
          if (countRs.isNotEmpty) {
            _totalRowCount = countRs.first.values.first as int?;
          }
        } catch (_) {
          _totalRowCount = null;
        }
      }

      final browseSql = _browseDataSql();
      final rs = await conn.execute(browseSql);

      if (!mounted) return;

      final cols = <String>[];
      if (rs.isNotEmpty) {
        cols.addAll(rs.first.keys);
      } else {
        cols.addAll(await conn.listColumnNames(table: widget.tableName));
      }

      final outRows = rs.map((row) {
        return cols.map((col) {
          final val = row[col];
          return val == null ? 'NULL' : val.toString();
        }).toList();
      }).toList();

      setState(() {
        _columnNames = cols;
        _rows = outRows;
        _rowsOnPage = outRows.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool get _canGoPrevious => _offset > 0;
  bool get _canGoNext {
    final total = _totalRowCount;
    if (total != null) {
      return _offset + _rowsOnPage < total;
    }
    return _rowsOnPage >= widget.limit;
  }

  void _goToPreviousPage() {
    if (!_canGoPrevious || _loading) return;
    setState(() {
      _offset -= widget.limit;
      if (_offset < 0) _offset = 0;
    });
    unawaited(_fetch());
  }

  void _goToNextPage() {
    if (!_canGoNext || _loading) return;
    setState(() {
      _offset += widget.limit;
    });
    unawaited(_fetch());
  }

  Future<void> _showDdlDialog() async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) return;
    final navigator = material.Navigator.of(context, rootNavigator: true);
    unawaited(showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const material.Center(
        child: material.CircularProgressIndicator(),
      ),
    ));
    try {
      final ddl = await conn.getObjectDdl(widget.tableName);
      if (navigator.canPop()) navigator.pop();
      if (!mounted) return;
      await showAppDialog<void>(
        context: context,
        builder: (ctx) => QueryaDialogCard(
          constraints: const material.BoxConstraints(maxWidth: 640, maxHeight: 500),
          child: material.Padding(
            padding: const material.EdgeInsets.all(20),
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.isView ? "View" : "Table"} DDL · ${widget.tableName}',
                ).semiBold().large(),
                const Gap(16),
                material.Expanded(
                  child: material.Container(
                    decoration: SqlEditorChrome.inlineFieldDecorationFromContext(ctx),
                    child: QueryaCodeEditor(
                      controller: material.TextEditingController(text: ddl),
                      language: QueryaCodeLanguage.sql,
                      readOnly: true,
                      fontSize: 12,
                      variant: QueryaCodeEditorVariant.material,
                      contentPadding: const material.EdgeInsets.all(12),
                    ),
                  ),
                ),
                const Gap(16),
                material.Align(
                  alignment: material.Alignment.centerRight,
                  child: OutlineButton(
                    onPressed: () => material.Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (navigator.canPop()) navigator.pop();
      if (!mounted) return;
      showAppToast(
        context: context,
        message: 'Failed to fetch DDL: $e',
        variant: AppToastVariant.error,
      );
    }
  }

  String _paginationLabel() {
    if (_columnNames.isEmpty && _rows.isEmpty) return '';
    final start = _offset + 1;
    final end = _offset + _rowsOnPage;
    final total = _totalRowCount;
    if (total != null) {
      return 'Showing $start-$end of $total row(s)';
    }
    return 'Showing $start-$end row(s)';
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
          right: material.BorderSide(
            color: cs.border.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
      ),
      child: material.Text(
        text,
        style: material.TextStyle(
          fontSize: 11,
          fontWeight:
              isHeader ? material.FontWeight.w600 : material.FontWeight.w400,
          color: isHeader ? cs.foreground : cs.mutedForeground,
        ),
      ),
    );
  }

  material.Widget _headerCell(ColorScheme cs, String name) {
    final isSorted = _sortColumn == name;
    return material.Expanded(
      child: material.MouseRegion(
        cursor: material.SystemMouseCursors.click,
        child: material.GestureDetector(
          behavior: material.HitTestBehavior.opaque,
          onTap: () => _toggleSort(name),
          child: material.Container(
            padding: const material.EdgeInsets.symmetric(horizontal: 10),
            alignment: material.Alignment.centerLeft,
            decoration: material.BoxDecoration(
              border: material.Border(
                right: material.BorderSide(
                  color: cs.border.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
            ),
            child: material.Row(
              children: [
                material.Expanded(
                  child: material.Text(
                    name,
                    overflow: material.TextOverflow.ellipsis,
                    style: material.TextStyle(
                      fontSize: 12,
                      fontWeight: material.FontWeight.w600,
                      color: isSorted ? cs.primary : cs.foreground,
                    ),
                  ),
                ),
                if (isSorted) ...[
                  const Gap(4),
                  material.Icon(
                    _sortAscending
                        ? material.Icons.arrow_upward_rounded
                        : material.Icons.arrow_downward_rounded,
                    size: 14,
                    color: cs.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  material.Widget _dataCell(ColorScheme cs, String value) {
    return material.Expanded(
      child: material.Container(
        padding: const material.EdgeInsets.symmetric(horizontal: 10),
        alignment: material.Alignment.centerLeft,
        decoration: material.BoxDecoration(
          border: material.Border(
            right: material.BorderSide(
              color: cs.border.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
        ),
        child: material.SelectableText(
          value,
          maxLines: 1,
          style: material.TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: value == 'NULL'
                ? cs.mutedForeground.withValues(alpha: 0.7)
                : cs.foreground,
          ),
        ),
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading && _columnNames.isEmpty) {
      return material.Container(
        color: cs.background,
        child: material.Center(
          child: material.Row(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              const material.SizedBox(
                width: 16,
                height: 16,
                child: material.CircularProgressIndicator(strokeWidth: 2),
              ),
              const Gap(12),
              const Text('Loading table data...').muted().small(),
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
              mainAxisAlignment: material.MainAxisAlignment.center,
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
                  onPressed: _connectAndLoad,
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
      return material.Container(
        color: cs.background,
        child: material.Center(
          child: material.Padding(
            padding: const material.EdgeInsets.all(32),
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                const Text('No columns returned').muted().small(),
                const Gap(24),
                OutlineButton(
                  onPressed: _connectAndLoad,
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

    const double rowHeight = 36;
    const double headerHeight = 40;
    final colCount = _columnNames.length;
    final title = '${widget.tableName}${widget.isView ? ' (view)' : ''}';

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
                if (widget.onNavigateHome != null) ...[
                  material.Tooltip(
                    message: 'Return to overview',
                    child: OutlineButton(
                      size: ButtonSize.small,
                      onPressed: widget.onNavigateHome,
                      leading: const material.Icon(
                        material.Icons.dns_outlined,
                        size: 14,
                      ),
                      child: const Text('Overview'),
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
                              OutlineButton(
                                size: ButtonSize.small,
                                onPressed: _loading
                                    ? null
                                    : () => unawaited(_showDdlDialog()),
                                child: const Text('DDL'),
                              ),
                              const Gap(4),
                              OutlineButton(
                                size: ButtonSize.small,
                                onPressed: _loading
                                    ? null
                                    : () => unawaited(_fetch()),
                                leading: const material.Icon(
                                  material.Icons.refresh_rounded,
                                  size: 14,
                                ),
                                child: const Text('Refresh'),
                              ),
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
                                onPressed: (!_canGoNext || _loading)
                                    ? null
                                    : _goToNextPage,
                                leading: const material.Icon(
                                  material.Icons.chevron_right_rounded,
                                  size: 16,
                                ),
                                child: const Text('Next'),
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
                                  final displayRowNum = _offset + rowIdx + 1;
                                  return material.RepaintBoundary(
                                    child: material.Container(
                                      height: rowHeight,
                                      decoration: material.BoxDecoration(
                                        color: isEven
                                            ? material.Colors.transparent
                                            : cs.muted.withValues(alpha: 0.12),
                                        border: material.Border(
                                          bottom: material.BorderSide(
                                            color: cs.border
                                                .withValues(alpha: 0.15),
                                          ),
                                        ),
                                      ),
                                      child: material.Row(
                                        children: [
                                          _rowNumberCell(cs, '$displayRowNum'),
                                          for (var c = 0; c < colCount; c++)
                                            _dataCell(cs,
                                                row.length > c ? row[c] : ''),
                                        ],
                                      ),
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
}
