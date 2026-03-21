import 'package:flutter/material.dart' as material;
import 'package:postgres/postgres.dart' as pg;
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/query_editor_tab.dart';
import 'package:querya_desktop/features/main_screen/results_tab.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _maxDisplayRows = 5000;

/// Ad-hoc SQL editor + results for a PostgreSQL connection (pgAdmin-style).
class PostgresSqlWorkspace extends material.StatefulWidget {
  const PostgresSqlWorkspace({
    super.key,
    required this.connectionRow,
  });

  final ConnectionRow connectionRow;

  @override
  material.State<PostgresSqlWorkspace> createState() =>
      _PostgresSqlWorkspaceState();
}

class _PostgresSqlWorkspaceState extends material.State<PostgresSqlWorkspace> {
  final _sqlController = material.TextEditingController();
  double _topFractionState = 0.65;

  PgLease? _lease;

  bool _running = false;
  String? _error;
  List<String> _columns = [];
  List<List<String>> _rows = [];
  int? _affectedRows;
  String? _statusLine;

  Future<void> _ensureLease() async {
    if (_lease != null && _lease!.connection.isConnected) return;
    _lease?.release();
    _lease = null;
    final lease = await PostgresService.instance.acquire(
      widget.connectionRow,
      database: widget.connectionRow.databaseName ?? 'postgres',
      mode: PgSessionMode.readWrite,
    );
    if (!mounted) {
      lease.release();
      return;
    }
    _lease = lease;
  }

  @override
  void dispose() {
    if (_running) {
      PostgresService.instance.interrupt(
        widget.connectionRow,
        database: widget.connectionRow.databaseName ?? 'postgres',
        mode: PgSessionMode.readWrite,
      );
    }
    _lease?.release();
    _sqlController.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    final sql = _sqlController.text.trim();
    if (sql.isEmpty) return;

    setState(() {
      _running = true;
      _error = null;
      _columns = [];
      _rows = [];
      _affectedRows = null;
      _statusLine = null;
    });

    try {
      await _ensureLease();
      final conn = _lease?.connection;
      if (conn == null || !conn.isConnected) {
        if (mounted) {
          setState(() {
            _error = 'Could not connect to PostgreSQL.';
            _running = false;
          });
        }
        return;
      }
      final result = await conn.execute(sql);

      if (!mounted) return;

      final schema = result.schema;
      final cols = <String>[];
      for (var i = 0; i < schema.columns.length; i++) {
        final c = schema.columns[i];
        cols.add(
          c.columnName?.isNotEmpty == true ? c.columnName! : '[$i]',
        );
      }

      final outRows = <List<String>>[];
      var n = 0;
      for (final row in result) {
        if (n >= _maxDisplayRows) break;
        outRows.add(row.map(_cellText).toList());
        n++;
      }

      setState(() {
        _columns = cols;
        _rows = outRows;
        _affectedRows = result.affectedRows;
        if (cols.isEmpty && outRows.isEmpty) {
          _statusLine =
              'Command completed. Rows affected: ${result.affectedRows}.';
        } else {
          final truncated = result.length > _maxDisplayRows;
          _statusLine = truncated
              ? 'Showing first $_maxDisplayRows of ${result.length} row(s).'
              : '${result.length} row(s).';
        }
        _running = false;
      });
    } on pg.ServerException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _running = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _running = false;
        });
      }
    }
  }

  static String _cellText(Object? v) {
    if (v == null) return 'NULL';
    return v.toString();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final topFlex = (_topFractionState * 100).round().clamp(20, 80);
    final bottomFlex = 100 - topFlex;

    return material.LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        return Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: topFlex,
              child: Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  _SqlToolbar(
                    onExecute: _running ? null : _execute,
                    running: _running,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: QueryEditorTab(controller: _sqlController),
                  ),
                ],
              ),
            ),
            _HorizontalResizeHandle(
              totalHeight: totalHeight,
              onDrag: (dy) {
                if (totalHeight <= 0) return;
                setState(() {
                  _topFractionState =
                      (_topFractionState + dy / totalHeight).clamp(0.2, 0.85);
                });
              },
            ),
            Expanded(
              flex: bottomFlex,
              child: Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  material.Container(
                    height: 44,
                    padding:
                        const material.EdgeInsets.symmetric(horizontal: 12),
                    decoration: material.BoxDecoration(
                      color: theme.colorScheme.muted.withValues(alpha: 0.6),
                    ),
                    alignment: material.Alignment.centerLeft,
                    child: Text('Data Output').semiBold().small(),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ResultsTab(
                      columns: _columns,
                      rows: _rows,
                      errorMessage: _error,
                      isLoading: _running,
                      affectedRows: _affectedRows,
                      statusLine: _statusLine,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SqlToolbar extends material.StatelessWidget {
  const _SqlToolbar({
    required this.onExecute,
    required this.running,
  });

  final Future<void> Function()? onExecute;
  final bool running;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    return material.Container(
      height: 44,
      padding: const material.EdgeInsets.symmetric(horizontal: 12),
      decoration: material.BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.6),
      ),
      child: material.Row(
        children: [
          Text('Query').semiBold().small(),
          const Spacer(),
          OutlineButton(
            onPressed: onExecute,
            leading: running
                ? material.SizedBox(
                    width: 16,
                    height: 16,
                    child: material.CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : const material.Icon(material.Icons.play_arrow_rounded, size: 18),
            child: const Text('Execute (F5)'),
          ),
        ],
      ),
    );
  }
}

class _HorizontalResizeHandle extends material.StatelessWidget {
  const _HorizontalResizeHandle({
    required this.totalHeight,
    required this.onDrag,
  });

  final double totalHeight;
  final void Function(double dy) onDrag;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return material.MouseRegion(
      cursor: material.SystemMouseCursors.resizeRow,
      child: material.GestureDetector(
        behavior: material.HitTestBehavior.opaque,
        onVerticalDragUpdate: (e) => onDrag(e.delta.dy),
        child: material.Container(
          height: 6,
          color: theme.border.withValues(alpha: 0.15),
        ),
      ),
    );
  }
}
