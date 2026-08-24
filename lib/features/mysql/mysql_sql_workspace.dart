import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:file_selector/file_selector.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/layout/vertical_split_pane.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/features/settings/sql_statement_timeout_dropdown.dart';
import 'package:querya_desktop/features/main_screen/query_editor_tab.dart';
import 'package:querya_desktop/features/main_screen/results_tab.dart';
import 'package:querya_desktop/features/main_screen/sql_editor_chrome.dart';
import 'package:querya_desktop/features/main_screen/sql_query_history_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Ad-hoc SQL editor + results for MySQL / MariaDB.
class MysqlSqlWorkspace extends material.StatefulWidget {
  const MysqlSqlWorkspace({
    super.key,
    required this.connectionRow,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final bool isReadOnly;

  @override
  material.State<MysqlSqlWorkspace> createState() => _MysqlSqlWorkspaceState();
}

class _MysqlSqlWorkspaceState extends material.State<MysqlSqlWorkspace> {
  final _sqlController = material.TextEditingController();
  final ValueNotifier<double> _topFraction = ValueNotifier(0.65);

  MysqlLease? _lease;

  bool _running = false;
  String? _error;
  List<String> _columns = [];
  List<List<String>> _rows = [];
  int? _affectedRows;
  String? _statusLine;

  int? _queryTimeoutSeconds;

  int _resultMaxRows = kDefaultSqlResultMaxRows;
  int _historyMaxEntries = kDefaultSqlHistoryMaxEntries;
  double _editorFontSize = kDefaultSqlEditorFontSize;

  late final VoidCallback _appSettingsListener;

  @override
  void initState() {
    super.initState();
    _appSettingsListener = () {
      unawaited(_loadWorkspaceSettings());
    };
    SqlWorkspaceSettingsRevision.listenable.addListener(_appSettingsListener);
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadWorkspaceSettings());
      _registerSqlEditorCommands();
    });
  }

  void _registerSqlEditorCommands() {
    if (!mounted) return;
    SqlEditorCommandBridge.instance.register(
      connectionId: widget.connectionRow.id,
      onNew: () => _sqlController.clear(),
      onOpen: () => unawaited(_openSqlFile()),
      onSave: () => unawaited(_saveSqlFile()),
    );
  }

  @override
  void didUpdateWidget(covariant MysqlSqlWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isReadOnly != widget.isReadOnly) {
      _lease?.release();
      _lease = null;
    }
  }

  Future<void> _loadWorkspaceSettings() async {
    final t = await AppSettings.instance.getMysqlSqlStmtTimeoutSeconds();
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
      mode: widget.isReadOnly ? MysqlSessionMode.readOnly : MysqlSessionMode.readWrite,
    );
    if (!mounted) {
      lease.release();
      return;
    }
    _lease = lease;
  }

  Duration? _statementTimeout() => _queryTimeoutSeconds == null
      ? null
      : Duration(seconds: _queryTimeoutSeconds!);

  @override
  void dispose() {
    SqlEditorCommandBridge.instance
        .unregister(connectionId: widget.connectionRow.id);
    SqlWorkspaceSettingsRevision.listenable
        .removeListener(_appSettingsListener);
    _topFraction.dispose();
    if (_running) {
      MysqlService.instance.interrupt(
        widget.connectionRow,
        database: _poolDatabaseKey(),
        mode: widget.isReadOnly ? MysqlSessionMode.readOnly : MysqlSessionMode.readWrite,
      );
    }
    _lease?.release();
    _sqlController.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    final selection = _sqlController.selection;
    String userSql;
    if (selection.isValid && !selection.isCollapsed) {
      userSql = selection.textInside(_sqlController.text).trim();
    } else {
      userSql = _sqlController.text.trim();
    }
    if (userSql.isEmpty) return;

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
      final rs =
          await conn.executeWithTimeout(userSql, timeout: to, iterable: true);

      if (!mounted) return;

      final cols = <String>[];
      for (final c in rs.cols) {
        cols.add(c.name.isNotEmpty ? c.name : 'col_${cols.length}');
      }

      // Convert while streaming — no Object? matrix + isolate double-copy (#421).
      final outRows = <List<String>>[];
      var n = 0;
      final cap = _resultMaxRows;
      var truncated = false;
      await for (final row in rs.rowsStream) {
        if (n >= cap) {
          truncated = true;
          break;
        }
        outRows.add(
          List.generate(
            row.numOfColumns,
            (i) => resultCellToDisplayString(row.colAt(i)),
          ),
        );
        n++;
        if (n % kResultStringConvertYieldEvery == 0) {
          await Future<void>.delayed(Duration.zero);
        }
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
          _statusLine = truncated
              ? 'Showing first $cap row(s) (result capped).'
              : '$n row(s).';
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
    } on TimeoutException catch (e) {
      unawaited(_lease?.connection.forceClose());
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

  Future<void> _openSqlFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'SQL query',
            extensions: ['sql'],
          ),
        ],
      );
      if (file == null) return;
      final text = await file.readAsString();
      if (!mounted) return;
      _sqlController.value = material.TextEditingValue(
        text: text,
        selection: material.TextSelection.collapsed(offset: text.length),
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context: context,
        message: 'Failed to open SQL file: $e',
        variant: AppToastVariant.error,
      );
    }
  }

  Future<void> _saveSqlFile() async {
    try {
      final name = 'query_${DateTime.now().toIso8601String().replaceAll(':', '-')}.sql';
      final location = await getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'SQL', extensions: ['sql']),
        ],
        suggestedName: name,
      );
      final path = location?.path;
      if (path == null || path.isEmpty) return;
      await File(path).writeAsString(_sqlController.text);
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context: context,
        message: 'Failed to save SQL file: $e',
        variant: AppToastVariant.error,
      );
    }
  }

  Future<void> _runTxCommand(String sql) async {
    _sqlController.value = material.TextEditingValue(
      text: sql,
      selection: material.TextSelection.collapsed(offset: sql.length),
    );
    await _execute();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);

    return Actions(
      actions: <Type, Action<Intent>>{
        NewSqlIntent: CallbackAction<NewSqlIntent>(
          onInvoke: (intent) {
            _sqlController.clear();
            return null;
          },
        ),
        OpenSqlIntent: CallbackAction<OpenSqlIntent>(
          onInvoke: (intent) {
            unawaited(_openSqlFile());
            return null;
          },
        ),
        SaveSqlIntent: CallbackAction<SaveSqlIntent>(
          onInvoke: (intent) {
            unawaited(_saveSqlFile());
            return null;
          },
        ),
      },
      child: material.CallbackShortcuts(
        bindings: {
          const material.SingleActivator(LogicalKeyboardKey.f5): () {
            if (!_running) unawaited(_execute());
          },
          const material.SingleActivator(
            LogicalKeyboardKey.enter,
            control: true,
          ): () {
            if (!_running) unawaited(_execute());
          },
          const material.SingleActivator(
            LogicalKeyboardKey.enter,
            meta: true,
          ): () {
            if (!_running) unawaited(_execute());
          },
          const material.SingleActivator(
            LogicalKeyboardKey.numpadEnter,
            control: true,
          ): () {
            if (!_running) unawaited(_execute());
          },
          const material.SingleActivator(
            LogicalKeyboardKey.numpadEnter,
            meta: true,
          ): () {
            if (!_running) unawaited(_execute());
          },
          const material.SingleActivator(
            LogicalKeyboardKey.keyR,
            control: true,
          ): () {
            if (!_running) unawaited(_execute());
          },
          const material.SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: true,
          ): () {
            if (!_running) unawaited(_execute());
          },
        },
        child: material.Focus(
          autofocus: true,
          child: VerticalSplitPane(
            fraction: _topFraction,
            maxFraction: 0.85,
            top: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MysqlSqlToolbar(
                  onExecute: _running ? null : _execute,
                  running: _running,
                  queryTimeoutSeconds: _queryTimeoutSeconds,
                  onQueryTimeoutChanged: _onStmtTimeoutChanged,
                  onOpenPreferences: () => showPreferencesDialog(context),
                  onOpenHistory: widget.connectionRow.id != null && !_running
                      ? () {
                          showSqlQueryHistoryDialog(
                            context: context,
                            connectionId: widget.connectionRow.id!,
                            databaseName: widget.connectionRow.databaseName,
                            sqlController: _sqlController,
                          );
                        }
                      : null,
                  onBegin: _running ? null : () => _runTxCommand('START TRANSACTION;'),
                  onCommit: _running ? null : () => _runTxCommand('COMMIT;'),
                  onRollback: _running ? null : () => _runTxCommand('ROLLBACK;'),
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
            bottom: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                material.Container(
                  constraints: const material.BoxConstraints(minHeight: 44),
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
        ),
      ),
    );
  }
}

class _MysqlSqlToolbar extends material.StatelessWidget {
  const _MysqlSqlToolbar({
    required this.onExecute,
    required this.running,
    required this.queryTimeoutSeconds,
    required this.onQueryTimeoutChanged,
    required this.onOpenPreferences,
    this.onOpenHistory,
    required this.onBegin,
    required this.onCommit,
    required this.onRollback,
  });

  final Future<void> Function()? onExecute;
  final bool running;
  final int? queryTimeoutSeconds;
  final void Function(int?) onQueryTimeoutChanged;
  final VoidCallback onOpenPreferences;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onBegin;
  final VoidCallback? onCommit;
  final VoidCallback? onRollback;

  @override
  material.Widget build(material.BuildContext context) {
    final accent = context.workbench.accent;
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: SqlEditorChrome.sqlToolbarDecoration(context),
      child: material.Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.Row(
            children: [
              const Text('Query').semiBold().small(),
              const Spacer(),
              OutlineButton(
                size: ButtonSize.small,
                onPressed: onOpenHistory,
                leading: material.Icon(
                  material.Icons.history_rounded,
                  size: 16,
                  color: accent,
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
                          color: accent,
                        ),
                      )
                    : material.Icon(
                        material.Icons.play_arrow_rounded,
                        size: 18,
                        color: accent,
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
                  SqlStatementTimeoutDropdown(
                    value: queryTimeoutSeconds,
                    onChanged: onQueryTimeoutChanged,
                    enabled: !running,
                  ),
                  const Gap(4),
                  IconButton.ghost(
                    onPressed: running ? null : onOpenPreferences,
                    icon: material.Icon(
                      material.Icons.settings_rounded,
                      size: 20,
                      color: accent,
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
