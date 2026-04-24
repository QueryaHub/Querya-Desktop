import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:postgres/postgres.dart' as pg;
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/database/postgres_sql.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/features/settings/sql_statement_timeout_dropdown.dart';
import 'package:querya_desktop/features/main_screen/query_editor_tab.dart';
import 'package:querya_desktop/features/main_screen/results_tab.dart';
import 'package:querya_desktop/features/main_screen/sql_query_history_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Ad-hoc SQL editor + results for a PostgreSQL connection (pgAdmin-style).
class PostgresSqlWorkspace extends material.StatefulWidget {
  const PostgresSqlWorkspace({
    super.key,
    required this.connectionRow,
    this.transactionOpenNotifier,
  });

  final ConnectionRow connectionRow;

  /// Updated when transaction state changes (for tab-switch warnings).
  final material.ValueNotifier<bool?>? transactionOpenNotifier;

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

  /// PostgreSQL default: each statement is its own transaction unless you use
  /// `BEGIN` / `BEGIN`+implicit when autocommit is off.
  bool _autocommit = true;

  /// `null` = use connection / URI [query_timeout] default from driver.
  int? _queryTimeoutSeconds;

  int _resultMaxRows = kDefaultSqlResultMaxRows;
  int _historyMaxEntries = kDefaultSqlHistoryMaxEntries;
  double _editorFontSize = kDefaultSqlEditorFontSize;

  /// `null` = unknown (older server or error).
  bool? _txOpen;

  late final VoidCallback _appSettingsListener;

  @override
  void initState() {
    super.initState();
    _appSettingsListener = () {
      unawaited(_loadWorkspaceSettings());
    };
    AppSettingsRevision.listenable.addListener(_appSettingsListener);
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadWorkspaceSettings());
    });
  }

  Future<void> _loadWorkspaceSettings() async {
    final t = await AppSettings.instance.getPostgresSqlStmtTimeoutSeconds();
    final rows = await AppSettings.instance.getSqlResultMaxRows();
    final hist = await AppSettings.instance.getSqlHistoryMaxEntries();
    final font = await AppSettings.instance.getSqlEditorFontSize();
    if (!mounted) return;
    setState(() {
      _queryTimeoutSeconds = t;
      _resultMaxRows = rows;
      _historyMaxEntries = hist;
      _editorFontSize = font;
    });
  }

  void _onStmtTimeoutChanged(int? v) {
    setState(() => _queryTimeoutSeconds = v);
    unawaited(AppSettings.instance.setPostgresSqlStmtTimeoutSeconds(v));
  }

  void _notifyTransactionOpen() {
    widget.transactionOpenNotifier?.value = _txOpen;
  }

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

  Duration? _statementTimeout() =>
      _queryTimeoutSeconds == null ? null : Duration(seconds: _queryTimeoutSeconds!);

  Future<void> _refreshTxStatus() async {
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) {
      if (mounted) setState(() => _txOpen = null);
      _notifyTransactionOpen();
      return;
    }
    final v = await conn.inOpenTransaction();
    if (mounted) setState(() => _txOpen = v);
    _notifyTransactionOpen();
  }

  Future<void> _runTxCommand(String cmd) async {
    setState(() {
      _running = true;
      _error = null;
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
      final to = _statementTimeout();
      await conn.execute(cmd, timeout: to);
      if (!mounted) return;
      setState(() {
        _columns = [];
        _rows = [];
        _affectedRows = null;
        _statusLine = 'OK: $cmd';
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
    } finally {
      await _refreshTxStatus();
    }
  }

  @override
  void dispose() {
    AppSettingsRevision.listenable.removeListener(_appSettingsListener);
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
    final userSql = _sqlController.text.trim();
    if (userSql.isEmpty) return;
    var sql = userSql;

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

      if (!_autocommit) {
        final inTx = await conn.inOpenTransaction() ?? false;
        if (!inTx && !shouldSkipImplicitBegin(sql)) {
          sql = 'BEGIN;\n$sql';
        }
      }

      final to = _statementTimeout();
      final result = await conn.execute(sql, timeout: to);

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
      final cap = _resultMaxRows;
      for (final row in result) {
        if (n >= cap) break;
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
          final truncated = result.length > cap;
          _statusLine = truncated
              ? 'Showing first $cap of ${result.length} row(s).'
              : '${result.length} row(s).';
        }
        _running = false;
      });
      final cid = widget.connectionRow.id;
      if (cid != null) {
        unawaited(
          LocalDb.instance.recordSqlQueryHistory(
            connectionId: cid,
            databaseName: widget.connectionRow.databaseName,
            sqlText: userSql,
            maxEntries: _historyMaxEntries,
          ),
        );
      }
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
    } finally {
      await _refreshTxStatus();
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
        return material.CallbackShortcuts(
          bindings: {
            const material.SingleActivator(LogicalKeyboardKey.f5): () {
              if (!_running) _execute();
            },
          },
          child: material.Focus(
            autofocus: true,
            child: Column(
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
                        autocommit: _autocommit,
                        onAutocommitChanged: (v) =>
                            setState(() => _autocommit = v),
                        queryTimeoutSeconds: _queryTimeoutSeconds,
                        onQueryTimeoutChanged: _onStmtTimeoutChanged,
                        onOpenPreferences: () =>
                            showPreferencesDialog(context),
                        onOpenHistory: widget.connectionRow.id != null &&
                                !_running
                            ? () {
                                showSqlQueryHistoryDialog(
                                  context: context,
                                  connectionId: widget.connectionRow.id!,
                                  databaseName:
                                      widget.connectionRow.databaseName,
                                  sqlController: _sqlController,
                                );
                              }
                            : null,
                        txOpen: _txOpen,
                        onBegin: _running
                            ? null
                            : () => _runTxCommand('BEGIN'),
                        onCommit: _running
                            ? null
                            : () => _runTxCommand('COMMIT'),
                        onRollback: _running
                            ? null
                            : () => _runTxCommand('ROLLBACK'),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: QueryEditorTab(
                          controller: _sqlController,
                          fontSize: _editorFontSize,
                        ),
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
                    crossAxisAlignment: material.CrossAxisAlignment.stretch,
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

class _SqlToolbar extends material.StatelessWidget {
  const _SqlToolbar({
    required this.onExecute,
    required this.running,
    required this.autocommit,
    required this.onAutocommitChanged,
    required this.queryTimeoutSeconds,
    required this.onQueryTimeoutChanged,
    required this.onOpenPreferences,
    this.onOpenHistory,
    required this.txOpen,
    required this.onBegin,
    required this.onCommit,
    required this.onRollback,
  });

  final Future<void> Function()? onExecute;
  final bool running;
  final bool autocommit;
  final void Function(bool) onAutocommitChanged;
  final int? queryTimeoutSeconds;
  final void Function(int?) onQueryTimeoutChanged;
  final VoidCallback onOpenPreferences;
  final VoidCallback? onOpenHistory;
  final bool? txOpen;
  final void Function()? onBegin;
  final void Function()? onCommit;
  final void Function()? onRollback;

  String _txLabel() {
    if (txOpen == null) return 'Transaction: —';
    return txOpen! ? 'Transaction: open' : 'Transaction: none';
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: material.BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.6),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.Row(
            children: [
              const Text('Query').semiBold().small(),
              const Gap(12),
              Text(_txLabel()).muted().small(),
              const Spacer(),
              OutlineButton(
                size: ButtonSize.small,
                onPressed: onOpenHistory,
                leading: const material.Icon(
                  material.Icons.history_rounded,
                  size: 16,
                ),
                child: const Text('History'),
              ),
              const Gap(8),
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
                  const Text('Autocommit').small(),
                  const Gap(6),
                  material.Switch(
                    value: autocommit,
                    onChanged: running ? null : onAutocommitChanged,
                  ),
                ],
              ),
              material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  const Text('Stmt timeout').small(),
                  const Gap(6),
                  SqlStatementTimeoutDropdown(
                    value: queryTimeoutSeconds,
                    onChanged: onQueryTimeoutChanged,
                    enabled: !running,
                  ),
                  const Gap(4),
                  IconButton.ghost(
                    onPressed: running ? null : onOpenPreferences,
                    icon: const material.Icon(
                      material.Icons.settings_rounded,
                      size: 20,
                    ),
                  ),
                ],
              ),
              OutlineButton(
                onPressed: onBegin,
                child: const Text('Begin'),
              ),
              OutlineButton(
                onPressed: onCommit,
                child: const Text('Commit'),
              ),
              OutlineButton(
                onPressed: onRollback,
                child: const Text('Rollback'),
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
