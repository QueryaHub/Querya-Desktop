import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:file_selector/file_selector.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/layout/vertical_split_pane.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/features/settings/sql_statement_timeout_dropdown.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
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
  final List<SqlQueryTabSession> _sessions = [];
  int _activeSessionIndex = 0;
  int _nextSessionId = 1;

  SqlQueryTabSession get _activeSession => _sessions[_activeSessionIndex];

  MysqlLease? _lease;

  int? _queryTimeoutSeconds;

  int _resultMaxRows = kDefaultSqlResultMaxRows;
  int _historyMaxEntries = kDefaultSqlHistoryMaxEntries;
  double _editorFontSize = kDefaultSqlEditorFontSize;

  late final VoidCallback _appSettingsListener;

  @override
  void initState() {
    super.initState();
    _sessions.add(
      SqlQueryTabSession(
        id: 'mysql_tab_1',
        title: 'Query 1',
      ),
    );
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
      onNew: _addNewTab,
      onOpen: () => unawaited(_openSqlFile()),
      onSave: () => unawaited(_saveSqlFile()),
      onExecute: () {
        if (!_activeSession.running) unawaited(_execute(_activeSession));
      },
      onCloseTab: () {
        if (_sessions.length > 1) unawaited(_closeTab(_activeSessionIndex));
      },
      onNextTab: _nextTab,
      onPrevTab: _prevTab,
      onOpenWithContent: (sql, filePath, title) {
        if (!mounted) return;
        final session = _activeSession;
        if (session.controller.text.trim().isEmpty && session.rows.isEmpty) {
          session.controller.value = material.TextEditingValue(
            text: sql,
            selection: material.TextSelection.collapsed(offset: sql.length),
          );
          session.title = title;
          session.filePath = filePath;
          setState(() {});
        } else {
          _addNewTab(initialSql: sql, title: title, filePath: filePath);
        }
      },
    );
  }

  void _addNewTab({String initialSql = '', String? title, String? filePath}) {
    setState(() {
      _nextSessionId++;
      final session = SqlQueryTabSession(
        id: 'mysql_tab_${DateTime.now().millisecondsSinceEpoch}_$_nextSessionId',
        title: title ?? 'Query $_nextSessionId',
        initialSql: initialSql,
        filePath: filePath,
        initialFraction:
            _sessions.isNotEmpty ? _activeSession.topFraction.value : 0.65,
      );
      _sessions.add(session);
      _activeSessionIndex = _sessions.length - 1;
    });
  }

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _sessions.length) return;
    if (_sessions.length <= 1) return;
    final session = _sessions[index];
    if (session.stagingBuffer != null && session.stagingBuffer!.isDirty) {
      final confirmed = await showUnsavedTabChangesDialog(
        context: context,
        tabTitle: session.title,
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() {
      _sessions.removeAt(index);
      session.dispose();
      if (_activeSessionIndex >= _sessions.length) {
        _activeSessionIndex = _sessions.length - 1;
      }
    });
  }

  void _nextTab() {
    if (_sessions.length <= 1) return;
    setState(() {
      _activeSessionIndex = (_activeSessionIndex + 1) % _sessions.length;
    });
  }

  void _prevTab() {
    if (_sessions.length <= 1) return;
    setState(() {
      _activeSessionIndex =
          (_activeSessionIndex - 1 + _sessions.length) % _sessions.length;
    });
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
    final anyRunning = _sessions.any((s) => s.running);
    if (anyRunning) {
      MysqlService.instance.interrupt(
        widget.connectionRow,
        database: _poolDatabaseKey(),
        mode: widget.isReadOnly ? MysqlSessionMode.readOnly : MysqlSessionMode.readWrite,
      );
    }
    _lease?.release();
    for (final s in _sessions) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _execute([SqlQueryTabSession? targetSession]) async {
    final session = targetSession ?? _activeSession;
    final selection = session.controller.selection;
    String userSql;
    if (selection.isValid && !selection.isCollapsed) {
      userSql = selection.textInside(session.controller.text).trim();
    } else {
      userSql = session.controller.text.trim();
    }
    if (userSql.isEmpty) return;

    final confirmDestructive =
        await AppSettings.instance.getConfirmDestructiveOperations();
    if (confirmDestructive) {
      final inspection = DestructiveSqlDetector.inspect(userSql);
      if (inspection.isDestructive) {
        if (!mounted) return;
        final confirmed = await showDestructiveQueryDialog(
          context: context,
          result: inspection,
          sql: userSql,
          connectionName: widget.connectionRow.name,
        );
        if (confirmed != true) return;
      }
    }

    setState(() {
      session.running = true;
      session.error = null;
      session.columns = [];
      session.rows = [];
      session.affectedRows = null;
      session.statusLine = null;
    });

    try {
      await _ensureLease();
      final conn = _lease?.connection;
      if (conn == null || !conn.isConnected) {
        if (mounted) {
          setState(() {
            session.error = 'Could not connect to MySQL.';
            session.running = false;
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
        session.columns = cols;
        session.rows = outRows;
        session.affectedRows = affected;
        session.lastExecutedSql = userSql;
        session.stagingBuffer?.dispose();
        session.stagingBuffer = cols.isNotEmpty
            ? DataGridStagingBuffer(columns: cols, rows: outRows)
            : null;
        if (cols.isEmpty && outRows.isEmpty) {
          session.statusLine = affected != null
              ? 'OK. Rows affected: $affected.'
              : 'Command completed.';
        } else {
          session.statusLine = truncated
              ? 'Showing first $cap row(s) (result capped).'
              : '$n row(s).';
        }
        session.running = false;
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
          session.error = e.toString();
          session.running = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          session.error = e.toString();
          session.running = false;
        });
      }
    }
  }

  Future<void> _applyStagedChanges([SqlQueryTabSession? targetSession]) async {
    final session = targetSession ?? _activeSession;
    if (session.stagingBuffer == null ||
        !session.stagingBuffer!.isDirty ||
        session.savingChanges) {
      return;
    }
    final target = session.lastExecutedSql != null
        ? SqlTableTargetExtractor.extract(session.lastExecutedSql!)
        : null;
    final tableName = target?.tableName ?? 'table';
    final schemaName = target?.schema;

    setState(() => session.savingChanges = true);
    try {
      final plan = session.stagingBuffer!.generateMutationPlan(
        dialect: SqlDialect.mysql,
        tableName: tableName,
        schema: schemaName,
      );
      if (plan.isEmpty) {
        setState(() => session.savingChanges = false);
        return;
      }

      final confirmed = await showDmlPreviewDialog(
        context: context,
        plan: plan,
      );
      if (confirmed != true) {
        setState(() => session.savingChanges = false);
        return;
      }

      await _ensureLease();
      final conn = _lease?.connection;
      if (conn == null || !conn.isConnected) {
        throw StateError('Could not connect to MySQL.');
      }

      for (final stmt in plan.statements) {
        await conn.execute(stmt.sql);
      }

      if (!mounted) return;
      final newRows = session.stagingBuffer!.effectiveRows;
      session.stagingBuffer?.dispose();
      setState(() {
        session.rows = newRows;
        session.stagingBuffer =
            DataGridStagingBuffer(columns: session.columns, rows: session.rows);
        session.savingChanges = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => session.savingChanges = false);
        await showAppDialog<void>(
          context: context,
          builder: (ctx) => QueryaDialogCard(
            constraints: const material.BoxConstraints(maxWidth: 420),
            child: material.Padding(
              padding: const material.EdgeInsets.all(20),
              child: material.Column(
                mainAxisSize: material.MainAxisSize.min,
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  Text('Save Changes Failed').semiBold().large(),
                  const Gap(8),
                  Text(e.toString()).muted().small(),
                  const Gap(20),
                  material.Align(
                    alignment: material.Alignment.centerRight,
                    child: PrimaryButton(
                      onPressed: () => material.Navigator.of(ctx).pop(),
                      child: const Text('OK'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
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
      final session = _activeSession;
      if (session.controller.text.trim().isEmpty && session.rows.isEmpty) {
        session.controller.value = material.TextEditingValue(
          text: text,
          selection: material.TextSelection.collapsed(offset: text.length),
        );
        session.title = file.name;
        session.filePath = file.path;
        setState(() {});
      } else {
        _addNewTab(initialSql: text, title: file.name, filePath: file.path);
      }
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
      final session = _activeSession;
      final existingPath = session.filePath;
      if (existingPath != null && existingPath.isNotEmpty) {
        await File(existingPath).writeAsString(session.controller.text);
        if (!mounted) return;
        showAppToast(
          context: context,
          message: 'Saved ${session.title}',
          variant: AppToastVariant.success,
        );
        return;
      }

      final suggested = session.title.endsWith('.sql')
          ? session.title
          : '${session.title}.sql';
      final location = await getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'SQL', extensions: ['sql']),
        ],
        suggestedName: suggested,
      );
      final path = location?.path;
      if (path == null || path.isEmpty) return;
      await File(path).writeAsString(session.controller.text);
      if (!mounted) return;
      setState(() {
        session.filePath = path;
        session.title = File(path).uri.pathSegments.last;
      });
      showAppToast(
        context: context,
        message: 'Saved to ${session.title}',
        variant: AppToastVariant.success,
      );
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
    _activeSession.controller.value = material.TextEditingValue(
      text: sql,
      selection: material.TextSelection.collapsed(offset: sql.length),
    );
    await _execute(_activeSession);
  }

  @override
  material.Widget build(material.BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        NewSqlIntent: CallbackAction<NewSqlIntent>(
          onInvoke: (intent) {
            _addNewTab();
            return null;
          },
        ),
        CloseSqlTabIntent: CallbackAction<CloseSqlTabIntent>(
          onInvoke: (intent) {
            if (_sessions.length > 1) {
              unawaited(_closeTab(_activeSessionIndex));
            }
            return null;
          },
        ),
        NextSqlTabIntent: CallbackAction<NextSqlTabIntent>(
          onInvoke: (intent) {
            _nextTab();
            return null;
          },
        ),
        PrevSqlTabIntent: CallbackAction<PrevSqlTabIntent>(
          onInvoke: (intent) {
            _prevTab();
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
          const material.SingleActivator(LogicalKeyboardKey.keyT, control: true): _addNewTab,
          const material.SingleActivator(LogicalKeyboardKey.keyT, meta: true): _addNewTab,
          const material.SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
            if (_sessions.length > 1) unawaited(_closeTab(_activeSessionIndex));
          },
          const material.SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
            if (_sessions.length > 1) unawaited(_closeTab(_activeSessionIndex));
          },
          const material.SingleActivator(LogicalKeyboardKey.tab, control: true): _nextTab,
          const material.SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): _prevTab,
          const material.SingleActivator(LogicalKeyboardKey.f5): () {
            if (!_activeSession.running) unawaited(_execute(_activeSession));
          },
          const material.SingleActivator(
            LogicalKeyboardKey.enter,
            control: true,
          ): () {
            if (!_activeSession.running) unawaited(_execute(_activeSession));
          },
          const material.SingleActivator(
            LogicalKeyboardKey.enter,
            meta: true,
          ): () {
            if (!_activeSession.running) unawaited(_execute(_activeSession));
          },
          const material.SingleActivator(
            LogicalKeyboardKey.numpadEnter,
            control: true,
          ): () {
            if (!_activeSession.running) unawaited(_execute(_activeSession));
          },
          const material.SingleActivator(
            LogicalKeyboardKey.numpadEnter,
            meta: true,
          ): () {
            if (!_activeSession.running) unawaited(_execute(_activeSession));
          },
          const material.SingleActivator(
            LogicalKeyboardKey.keyR,
            control: true,
          ): () {
            if (!_activeSession.running) unawaited(_execute(_activeSession));
          },
          const material.SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: true,
          ): () {
            if (!_activeSession.running) unawaited(_execute(_activeSession));
          },
        },
        child: material.Focus(
          autofocus: true,
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            children: [
              SqlQueryTabBar(
                sessions: _sessions,
                selectedIndex: _activeSessionIndex,
                onSelect: (index) => setState(() => _activeSessionIndex = index),
                onAdd: _addNewTab,
                onClose: _sessions.length > 1
                    ? (index) => unawaited(_closeTab(index))
                    : null,
              ),
              material.Expanded(
                child: material.IndexedStack(
                  index: _activeSessionIndex,
                  children: [
                    for (final session in _sessions)
                      _buildSessionPane(context, session),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  material.Widget _buildSessionPane(
    material.BuildContext context,
    SqlQueryTabSession session,
  ) {
    final theme = Theme.of(context);
    return VerticalSplitPane(
      fraction: session.topFraction,
      maxFraction: 0.85,
      top: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MysqlSqlToolbar(
            onExecute: session.running ? null : () => _execute(session),
            running: session.running,
            queryTimeoutSeconds: _queryTimeoutSeconds,
            onQueryTimeoutChanged: _onStmtTimeoutChanged,
            onOpenPreferences: () => showPreferencesDialog(context),
            onOpenHistory: widget.connectionRow.id != null && !session.running
                ? () {
                    showSqlQueryHistoryDialog(
                      context: context,
                      connectionId: widget.connectionRow.id!,
                      databaseName: widget.connectionRow.databaseName,
                      sqlController: session.controller,
                    );
                  }
                : null,
            onBegin: session.running ? null : () => _runTxCommand('START TRANSACTION;'),
            onCommit: session.running ? null : () => _runTxCommand('COMMIT;'),
            onRollback: session.running ? null : () => _runTxCommand('ROLLBACK;'),
          ),
          const Divider(height: 1),
          Expanded(
            child: QueryEditorTab(
              controller: session.controller,
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
              columns: session.columns,
              rows: session.rows,
              errorMessage: session.error,
              isLoading: session.running,
              affectedRows: session.affectedRows,
              statusLine: session.statusLine,
              stagingBuffer: session.stagingBuffer,
              onApplyChanges:
                  widget.isReadOnly ? null : () => _applyStagedChanges(session),
              isSaving: session.savingChanges,
            ),
          ),
        ],
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
