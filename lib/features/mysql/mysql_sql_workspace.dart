import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/query_editor_tab.dart';
import 'package:querya_desktop/features/main_screen/results_tab.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _maxDisplayRows = 5000;

/// Ad-hoc SQL editor + results for MySQL / MariaDB.
class MysqlSqlWorkspace extends material.StatefulWidget {
  const MysqlSqlWorkspace({
    super.key,
    required this.connectionRow,
  });

  final ConnectionRow connectionRow;

  @override
  material.State<MysqlSqlWorkspace> createState() =>
      _MysqlSqlWorkspaceState();
}

class _MysqlSqlWorkspaceState extends material.State<MysqlSqlWorkspace> {
  final _sqlController = material.TextEditingController();
  double _topFractionState = 0.65;

  MysqlLease? _lease;

  bool _running = false;
  String? _error;
  List<String> _columns = [];
  List<List<String>> _rows = [];
  int? _affectedRows;
  String? _statusLine;

  int? _queryTimeoutSeconds;

  @override
  void initState() {
    super.initState();
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadStmtTimeoutSetting());
    });
  }

  Future<void> _loadStmtTimeoutSetting() async {
    final t = await AppSettings.instance.getMysqlSqlStmtTimeoutSeconds();
    if (!mounted) return;
    setState(() => _queryTimeoutSeconds = t);
  }

  void _onStmtTimeoutChanged(int? v) {
    setState(() => _queryTimeoutSeconds = v);
    unawaited(AppSettings.instance.setMysqlSqlStmtTimeoutSeconds(v));
  }

  String _poolDatabaseKey() => widget.connectionRow.databaseName ?? '';

  Future<void> _ensureLease() async {
    if (_lease != null && _lease!.connection.isConnected) return;
    _lease?.release();
    _lease = null;
    final lease = await MysqlService.instance.acquire(
      widget.connectionRow,
      database: _poolDatabaseKey(),
      mode: MysqlSessionMode.readWrite,
    );
    if (!mounted) {
      lease.release();
      return;
    }
    _lease = lease;
  }

  Duration? _statementTimeout() =>
      _queryTimeoutSeconds == null ? null : Duration(seconds: _queryTimeoutSeconds!);

  @override
  void dispose() {
    if (_running) {
      MysqlService.instance.interrupt(
        widget.connectionRow,
        database: _poolDatabaseKey(),
        mode: MysqlSessionMode.readWrite,
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
            _error = 'Could not connect to MySQL.';
            _running = false;
          });
        }
        return;
      }

      final to = _statementTimeout();
      final rs = await conn.executeWithTimeout(sql, timeout: to);

      if (!mounted) return;

      final cols = <String>[];
      for (final c in rs.cols) {
        cols.add(c.name.isNotEmpty ? c.name : 'col_${cols.length}');
      }

      final outRows = <List<String>>[];
      var n = 0;
      for (final row in rs.rows) {
        if (n >= _maxDisplayRows) break;
        outRows.add(
          List.generate(
            row.numOfColumns,
            (i) => row.colAt(i) ?? 'NULL',
          ),
        );
        n++;
      }

      int? affected;
      if (cols.isEmpty && outRows.isEmpty) {
        affected = _affectedInt(rs.affectedRows);
      }

      setState(() {
        _columns = cols;
        _rows = outRows;
        _affectedRows = affected;
        if (cols.isEmpty && outRows.isEmpty) {
          _statusLine = affected != null
              ? 'OK. Rows affected: $affected.'
              : 'Command completed.';
        } else {
          final total = rs.numOfRows;
          final truncated = total > _maxDisplayRows;
          _statusLine = truncated
              ? 'Showing first $_maxDisplayRows of $total row(s).'
              : '$total row(s).';
        }
        _running = false;
      });
    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
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

  static int? _affectedInt(BigInt v) {
    if (v == BigInt.zero) return null;
    return v.toInt();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final topFlex = (_topFractionState * 100).round().clamp(20, 80);
    final bottomFlex = 100 - topFlex;

    return material.LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        return material.CallbackShortcuts(
          bindings: {
            const material.SingleActivator(LogicalKeyboardKey.f5): () {
              if (!_running) {
                unawaited(_execute());
              }
            },
          },
          child: material.Focus(
            autofocus: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: topFlex,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MysqlSqlToolbar(
                        onExecute: _running ? null : _execute,
                        running: _running,
                        queryTimeoutSeconds: _queryTimeoutSeconds,
                        onQueryTimeoutChanged: _onStmtTimeoutChanged,
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
                      _topFractionState = (_topFractionState + dy / totalHeight)
                          .clamp(0.2, 0.85);
                    });
                  },
                ),
                Expanded(
                  flex: bottomFlex,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      material.Container(
                        height: 44,
                        padding: const material.EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        decoration: material.BoxDecoration(
                          color: theme.colorScheme.muted.withValues(alpha: 0.6),
                        ),
                        alignment: material.Alignment.centerLeft,
                        child: const Text('Data Output').semiBold().small(),
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
            ),
          ),
        );
      },
    );
  }
}

class _MysqlSqlToolbar extends material.StatelessWidget {
  const _MysqlSqlToolbar({
    required this.onExecute,
    required this.running,
    required this.queryTimeoutSeconds,
    required this.onQueryTimeoutChanged,
  });

  final Future<void> Function()? onExecute;
  final bool running;
  final int? queryTimeoutSeconds;
  final void Function(int?) onQueryTimeoutChanged;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: material.BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.6),
      ),
      child: material.Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.Row(
            children: [
              const Text('Query').semiBold().small(),
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
                    : const material.Icon(
                        material.Icons.play_arrow_rounded,
                        size: 18,
                      ),
                child: const Text('Execute (F5)'),
              ),
            ],
          ),
          const Gap(8),
          material.Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: material.WrapCrossAlignment.center,
            children: [
              material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  const Text('Stmt timeout').small(),
                  const Gap(6),
                  material.DropdownButton<int?>(
                    value: queryTimeoutSeconds,
                    onChanged: running ? null : onQueryTimeoutChanged,
                    items: const [
                      material.DropdownMenuItem<int?>(
                        value: null,
                        child: material.Text('No limit'),
                      ),
                      material.DropdownMenuItem(
                        value: 10,
                        child: material.Text('10 s'),
                      ),
                      material.DropdownMenuItem(
                        value: 30,
                        child: material.Text('30 s'),
                      ),
                      material.DropdownMenuItem(
                        value: 60,
                        child: material.Text('60 s'),
                      ),
                      material.DropdownMenuItem(
                        value: 120,
                        child: material.Text('2 min'),
                      ),
                      material.DropdownMenuItem(
                        value: 300,
                        child: material.Text('5 min'),
                      ),
                      material.DropdownMenuItem(
                        value: 600,
                        child: material.Text('10 min'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
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
