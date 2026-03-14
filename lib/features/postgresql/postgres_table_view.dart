import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
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
    this.limit = _defaultLimit,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String schema;
  final String tableName;
  final bool isView;
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
  int _totalRows = 0;

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
        oldWidget.tableName != widget.tableName) {
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

  static String _quoteIdentifier(String name) {
    return '"${name.replaceAll('"', '""')}"';
  }

  Future<void> _connectAndLoad() async {
    _disconnectCurrent();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _columnNames = [];
      _rows = [];
      _totalRows = 0;
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
      await _fetch();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetch() async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final schemaQ = _quoteIdentifier(widget.schema);
    final tableQ = _quoteIdentifier(widget.tableName);
    final sql = 'SELECT * FROM $schemaQ.$tableQ LIMIT ${widget.limit}';
    try {
      final result = await conn.execute(sql);
      if (!mounted) return;

      final colNames = List<String>.generate(
        result.schema.columns.length,
        (i) => result.schema.columns[i].columnName ?? 'col_$i',
      );

      // Convert to plain strings in isolate to avoid blocking UI
      final rawRows = result.map((row) {
        return List<dynamic>.generate(row.length, (i) => row[i]);
      }).toList();

      final stringRows = await compute(_convertRows, rawRows);

      if (!mounted) return;
      setState(() {
        _columnNames = colNames;
        _rows = stringRows;
        _totalRows = stringRows.length;
        _loading = false;
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

  static List<List<String>> _convertRows(List<List<dynamic>> rawRows) {
    return rawRows.map((row) {
      return row.map((value) {
        if (value == null) return 'NULL';
        if (value is DateTime) return value.toIso8601String();
        return value.toString();
      }).toList();
    }).toList();
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
                  onPressed: _fetch,
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
                  widget.isView
                      ? material.Icons.view_agenda_rounded
                      : material.Icons.table_chart_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const Gap(8),
                material.Expanded(
                  child: material.Text(
                    '${widget.schema}.${widget.tableName}'
                        '${widget.isView ? ' (view)' : ''}',
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
                    '$_totalRows rows',
                    style: material.TextStyle(
                        fontSize: 11, color: cs.mutedForeground),
                  ),
                ),
                const Gap(8),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _fetch,
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
                                itemCount: _totalRows,
                                itemExtent: rowHeight,
                                itemBuilder: (context, rowIdx) {
                                  final row = _rows[rowIdx];
                                  final isEven = rowIdx % 2 == 0;
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
                                            '${rowIdx + 1}'),
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
