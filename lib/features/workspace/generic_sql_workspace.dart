import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:file_selector/file_selector.dart';
import 'package:querya_desktop/core/storage/mutation_audit_recorder.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/layout/vertical_split_pane.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/ui/querya_shell_status.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/features/settings/sql_statement_timeout_dropdown.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/destructive_query_dialog.dart';
import 'package:querya_desktop/features/workspace/dml_preview_dialog.dart';
import 'package:querya_desktop/features/workspace/query_editor_tab.dart';
import 'package:querya_desktop/features/workspace/results_tab.dart';
import 'package:querya_desktop/features/workspace/sql_editor_chrome.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:querya_desktop/features/workspace/sql_query_history_dialog.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_bar.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_session.dart';
import 'package:querya_desktop/features/workspace/sql_result_grid_schema.dart';
import 'package:querya_desktop/features/workspace/table_view_staging.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Reusable base SQL workspace supporting multi-tab editing, statement execution,
/// destructive query confirmations, unsaved changes guards, DML staging and result grids.
class GenericSqlWorkspace extends material.StatefulWidget {
  const GenericSqlWorkspace({
    super.key,
    required this.connectionRow,
    required this.delegate,
    required this.dialect,
    this.sessionPrefix = 'query',
    this.initialSql,
    this.initialTabTitle,
    this.transactionOpenNotifier,
    this.isReadOnly = false,
    this.supportsAutocommit = false,
    this.initialAutocommit = true,
    this.onAutocommitChanged,
    this.supportsStmtTimeout = true,
    this.getStoredTimeoutSeconds,
    this.setStoredTimeoutSeconds,
    this.effectiveDatabaseName,
    this.extraToolbarTrailing,
    this.errorActionBuilder,
    this.headerBadge,
  });

  final ConnectionRow connectionRow;
  final SqlExecutionDelegate delegate;
  final SqlDialect dialect;
  final String sessionPrefix;
  final String? initialSql;
  final String? initialTabTitle;
  final material.ValueNotifier<bool?>? transactionOpenNotifier;
  final bool isReadOnly;

  final bool supportsAutocommit;
  final bool initialAutocommit;
  final void Function(bool value)? onAutocommitChanged;

  final bool supportsStmtTimeout;
  final Future<int?> Function()? getStoredTimeoutSeconds;
  final Future<void> Function(int? value)? setStoredTimeoutSeconds;

  final String Function()? effectiveDatabaseName;
  final material.Widget? Function(material.BuildContext context, SqlQueryTabSession session)? extraToolbarTrailing;
  final material.Widget? Function(material.BuildContext context, SqlQueryTabSession session)? errorActionBuilder;
  final material.Widget? headerBadge;

  @override
  material.State<GenericSqlWorkspace> createState() => GenericSqlWorkspaceState();
}

class GenericSqlWorkspaceState extends material.State<GenericSqlWorkspace> {
  final List<SqlQueryTabSession> _sessions = [];
  int _activeSessionIndex = 0;
  int _nextSessionId = 1;

  SqlQueryTabSession get _activeSession => _sessions[_activeSessionIndex];

  SqlQueryTabSession get activeSession => _activeSession;

  final Map<String, material.Widget> _paneCache = {};

  void invalidatePane(SqlQueryTabSession session) =>
      _paneCache.remove(session.id);

  void invalidateAllPanes() => _paneCache.clear();

  int paneBuildCount = 0;

  void debugRebuildActivePane() {
    invalidatePane(_activeSession);
    setState(() {});
  }

  bool? _txOpen;
  bool _autocommit = true;
  int? _queryTimeoutSeconds;

  int _resultMaxRows = kDefaultSqlResultMaxRows;
  int _historyMaxEntries = kDefaultSqlHistoryMaxEntries;
  double _editorFontSize = kDefaultSqlEditorFontSize;

  late final VoidCallback _appSettingsListener;

  String get effectiveDatabase =>
      widget.effectiveDatabaseName?.call() ??
      widget.connectionRow.databaseName ??
      '';

  @override
  void initState() {
    super.initState();
    _autocommit = widget.initialAutocommit;
    _sessions.add(
      SqlQueryTabSession(
        id: '${widget.sessionPrefix}_tab_1',
        title: widget.initialTabTitle ?? 'Query 1',
        initialSql: widget.initialSql,
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

  @override
  void didUpdateWidget(covariant GenericSqlWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isReadOnly != widget.isReadOnly) {
      invalidateAllPanes();
    }
  }

  @override
  void dispose() {
    SqlEditorCommandBridge.instance
        .unregister(connectionId: widget.connectionRow.id);
    SqlWorkspaceSettingsRevision.listenable
        .removeListener(_appSettingsListener);
    final anyRunning = _sessions.any((s) => s.running);
    if (anyRunning) {
      unawaited(widget.delegate.cancelQuery());
    }
    for (final s in _sessions) {
      s.dispose();
    }
    _sessions.clear();
    _paneCache.clear();
    widget.delegate.dispose();
    super.dispose();
  }

  void _registerSqlEditorCommands() {
    if (!mounted) return;
    SqlEditorCommandBridge.instance.register(
      connectionId: widget.connectionRow.id,
      onNew: addNewTab,
      onOpen: () => unawaited(openSqlFile()),
      onSave: () => unawaited(saveSqlFile()),
      onExecute: () {
        if (!_activeSession.running) unawaited(execute(_activeSession));
      },
      onCloseTab: () {
        if (_sessions.length > 1) unawaited(closeTab(_activeSessionIndex));
      },
      onNextTab: nextTab,
      onPrevTab: prevTab,
      onFormat: () {
        _activeSession.formatSql();
        invalidatePane(_activeSession);
        setState(() {});
      },
      onClear: () {
        _activeSession.clearSql();
        invalidatePane(_activeSession);
        setState(() {});
      },
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
          invalidatePane(session);
          setState(() {});
        } else {
          addNewTab(initialSql: sql, title: title, filePath: filePath);
        }
      },
    );
  }

  void addNewTab({String? initialSql, String? title, String? filePath}) {
    setState(() {
      _nextSessionId++;
      final session = SqlQueryTabSession(
        id: '${widget.sessionPrefix}_tab_${DateTime.now().millisecondsSinceEpoch}_$_nextSessionId',
        title: title ?? 'Query $_nextSessionId',
        initialSql: initialSql ?? '',
        filePath: filePath,
        initialFraction:
            _sessions.isNotEmpty ? _activeSession.topFraction.value : 0.65,
      );
      _sessions.add(session);
      _activeSessionIndex = _sessions.length - 1;
    });
  }

  /// Opens the ER diagram tab (or focuses the existing one).
  void openDiagramTab() {
    final existing = _sessions.indexWhere((s) => s.isDiagram);
    if (existing >= 0) {
      setState(() => _activeSessionIndex = existing);
      return;
    }
    setState(() {
      _nextSessionId++;
      _sessions.add(SqlQueryTabSession(
        id: '${widget.sessionPrefix}_diagram_$_nextSessionId',
        title: 'Diagram',
        isDiagram: true,
      ));
      _activeSessionIndex = _sessions.length - 1;
    });
  }

  void _openTableFromDiagram(String table) {
    final q = switch (widget.dialect) {
      SqlDialect.mysql => '`$table`',
      _ => '"$table"',
    };
    addNewTab(initialSql: 'SELECT * FROM $q LIMIT 100;', title: table);
    final session = _activeSession;
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(execute(session));
    });
  }

  Future<void> closeTab(int index) async {
    if (index < 0 || index >= _sessions.length) return;
    if (_sessions.length <= 1) return;
    final session = _sessions[index];
    if (session.isDirty) {
      final hasDirtyStaging =
          session.stagingBuffer != null && session.stagingBuffer!.isDirty;
      final hasUnsavedText = session.isModified ||
          (session.filePath == null && session.controller.text.trim().isNotEmpty);
      final String message;
      if (hasDirtyStaging && hasUnsavedText) {
        message =
            'This query tab contains unsaved query text and staged database changes. Closing the tab will discard them.';
      } else if (hasDirtyStaging) {
        message =
            'This query tab contains staged database changes that have not been applied yet. Closing the tab will discard these changes.';
      } else {
        message =
            'This query tab contains unsaved SQL query text. Closing the tab will discard your changes.';
      }
      final confirmed = await showUnsavedTabChangesDialog(
        context: context,
        tabTitle: session.title,
        message: message,
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() {
      _sessions.removeAt(index);
      session.dispose();
      _paneCache.remove(session.id);
      if (_activeSessionIndex >= _sessions.length) {
        _activeSessionIndex = _sessions.length - 1;
      }
    });
  }

  void nextTab() {
    if (_sessions.length <= 1) return;
    setState(() {
      _activeSessionIndex = (_activeSessionIndex + 1) % _sessions.length;
    });
  }

  void prevTab() {
    if (_sessions.length <= 1) return;
    setState(() {
      _activeSessionIndex =
          (_activeSessionIndex - 1 + _sessions.length) % _sessions.length;
    });
  }

  Future<void> _loadWorkspaceSettings() async {
    int? t;
    if (widget.getStoredTimeoutSeconds != null) {
      t = await widget.getStoredTimeoutSeconds!();
    }
    final rows = await AppSettings.instance.getSqlResultMaxRows();
    final hist = await AppSettings.instance.getSqlHistoryMaxEntries();
    final font = await AppSettings.instance.getSqlEditorFontSize();
    if (!mounted) return;
    invalidateAllPanes();
    setState(() {
      _queryTimeoutSeconds = t;
      _resultMaxRows = rows;
      _historyMaxEntries = hist;
      _editorFontSize = font;
    });
  }

  void _onStmtTimeoutChanged(int? v) {
    invalidateAllPanes();
    setState(() => _queryTimeoutSeconds = v);
    if (widget.setStoredTimeoutSeconds != null) {
      unawaited(widget.setStoredTimeoutSeconds!(v));
    }
  }

  void _notifyTransactionOpen() {
    widget.transactionOpenNotifier?.value = _txOpen;
  }

  Future<void> refreshTxStatus() async {
    if (!widget.delegate.supportsTransactions) return;
    final v = await widget.delegate.checkTransactionOpen();
    if (mounted) {
      invalidateAllPanes();
      setState(() => _txOpen = v);
    }
    _notifyTransactionOpen();
  }

  Duration? get statementTimeout => _queryTimeoutSeconds == null
      ? null
      : Duration(seconds: _queryTimeoutSeconds!);

  Future<void> runTxCommand(String cmd) async {
    final session = _activeSession;
    invalidatePane(session);
    setState(() {
      session.running = true;
      session.error = null;
    });
    try {
      await widget.delegate.runTransactionCommand(cmd, timeout: statementTimeout);
      if (!mounted) return;
      invalidatePane(session);
      setState(() {
        session.columns = [];
        session.rows = [];
        session.affectedRows = null;
        session.statusLine = 'OK: $cmd';
        session.running = false;
      });
    } on TimeoutException catch (e) {
      if (mounted) {
        invalidatePane(session);
        setState(() {
          session.error = 'Query timed out: ${e.message ?? e}';
          session.running = false;
        });
      }
    } catch (e) {
      if (mounted) {
        invalidatePane(session);
        setState(() {
          session.error = e.toString();
          session.running = false;
        });
      }
    } finally {
      await refreshTxStatus();
    }
  }

  Future<void> execute([SqlQueryTabSession? targetSession]) async {
    final session = targetSession ?? _activeSession;
    if (session.running) return;

    final selection = session.controller.selection;
    String userSql;
    if (selection.isValid && !selection.isCollapsed) {
      userSql = selection.textInside(session.controller.text).trim();
    } else {
      userSql = session.controller.text.trim();
    }
    if (userSql.isEmpty) return;

    final safeToProceed = await confirmDiscardTableEditsIfDirty(
      context: context,
      buffer: session.stagingBuffer,
      tableTitle: session.title,
    );
    if (!safeToProceed) return;
    if (session.stagingBuffer != null && session.stagingBuffer!.isDirty) {
      session.stagingBuffer?.dispose();
      session.stagingBuffer = null;
    }

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

    invalidatePane(session);
    setState(() {
      session.running = true;
      session.error = null;
      session.columns = [];
      session.rows = [];
      session.affectedRows = null;
      session.statusLine = null;
      session.resultGridPrimaryKeys = const [];
      session.resultGridColumnDataTypes = null;
      session.resultGridColumnMeta = null;
    });
    QueryaShellStatus.instance.beginBusy(message: 'Running query…');
    final sw = Stopwatch()..start();

    try {
      final result = await widget.delegate.executeQuery(
        userSql,
        limit: _resultMaxRows,
        timeout: statementTimeout,
      );

      if (!mounted) return;

      final cols = result.columns;
      final outRows = result.rows;

      final gridSchema = await widget.delegate.resolveTableSchema(userSql, cols);
      final pks = gridSchema.primaryKeys;
      final editHint = gridSchema.editHint(cols);
      final canSave = sqlResultGridSaveEnabled(
        sql: userSql,
        resultColumns: cols,
        primaryKeys: pks,
      );

      invalidatePane(session);
      setState(() {
        session.columns = cols;
        session.rows = outRows;
        session.affectedRows = result.affectedRows;
        session.lastExecutedSql = userSql;
        session.resultGridPrimaryKeys = canSave ? pks : const [];
        session.resultGridColumnDataTypes = gridSchema.columnDataTypes;
        session.resultGridColumnMeta = gridSchema.columnMeta;
        session.stagingBuffer?.dispose();
        session.stagingBuffer = canSave
            ? DataGridStagingBuffer(
                columns: cols,
                rows: outRows,
                primaryKeys: pks,
              )
            : null;

        if (result.statusMessage != null) {
          session.statusLine = withEditHint(result.statusMessage!, editHint);
        } else if (cols.isEmpty && outRows.isEmpty) {
          session.statusLine = result.affectedRows != null
              ? 'OK. Rows affected: ${result.affectedRows}.'
              : 'Command completed.';
        } else {
          final n = outRows.length;
          final cap = _resultMaxRows;
          session.statusLine = withEditHint(
            result.isTruncated
                ? 'Showing first $cap row(s) (result capped).'
                : '$n row(s).',
            editHint,
          );
        }
        session.running = false;
      });

      sw.stop();
      final duration = result.elapsed ?? sw.elapsed;
      QueryaShellStatus.instance.reportQueryResult(
        duration: duration,
        rowCount: outRows.length,
        columnCount: cols.length,
        message: session.statusLine,
      );

      auditSqlExecution(
        connection: widget.connectionRow,
        databaseName: effectiveDatabase,
        sql: userSql,
        rowsAffected: result.affectedRows,
        source: MutationAuditSource.sqlEditor,
      );

      final cid = widget.connectionRow.id;
      if (cid != null) {
        unawaited(
          LocalDb.instance.recordSqlQueryHistory(
            connectionId: cid,
            databaseName: effectiveDatabase,
            sqlText: userSql,
            maxEntries: _historyMaxEntries,
          ),
        );
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        invalidatePane(session);
        setState(() {
          session.error = 'Query timed out: ${e.message ?? e}';
          session.running = false;
        });
        QueryaShellStatus.instance.endBusy();
      }
    } catch (e) {
      if (mounted) {
        invalidatePane(session);
        setState(() {
          session.error = e.toString();
          session.running = false;
        });
        QueryaShellStatus.instance.endBusy();
      }
    } finally {
      await refreshTxStatus();
    }
  }

  Future<void> applyStagedChanges([SqlQueryTabSession? targetSession]) async {
    final session = targetSession ?? _activeSession;
    if (widget.isReadOnly ||
        session.stagingBuffer == null ||
        !session.stagingBuffer!.isDirty ||
        session.savingChanges) {
      return;
    }
    final target = session.lastExecutedSql != null
        ? SqlTableTargetExtractor.extract(session.lastExecutedSql!)
        : null;
    if (target == null ||
        !sqlResultGridSaveEnabled(
          sql: session.lastExecutedSql,
          resultColumns: session.columns,
          primaryKeys: session.resultGridPrimaryKeys,
        )) {
      return;
    }

    final schemaName = target.schema ??
        (widget.connectionRow.databaseName?.trim().isNotEmpty == true
            ? widget.connectionRow.databaseName!.trim()
            : null);

    invalidatePane(session);
    setState(() => session.savingChanges = true);

    try {
      final plan = session.stagingBuffer!.generateMutationPlan(
        dialect: widget.dialect,
        tableName: target.tableName,
        schema: schemaName,
        primaryKeys: session.resultGridPrimaryKeys,
        columnDataTypes: session.resultGridColumnDataTypes,
        columnMeta: session.resultGridColumnMeta,
      );
      if (plan.isEmpty) {
        invalidatePane(session);
        setState(() => session.savingChanges = false);
        return;
      }

      final confirmed = await showDmlPreviewDialog(
        context: context,
        plan: plan,
      );
      if (confirmed != true) {
        invalidatePane(session);
        setState(() => session.savingChanges = false);
        return;
      }

      await widget.delegate.applyStagedMutations(
        plan: plan,
        timeout: statementTimeout,
      );
      await refreshTxStatus();
      auditMutationPlan(
        connection: widget.connectionRow,
        databaseName: effectiveDatabase,
        plan: plan,
        source: MutationAuditSource.sqlEditor,
      );

      if (!mounted) return;
      final newRows = session.stagingBuffer!.committedRows;
      session.stagingBuffer?.dispose();
      invalidatePane(session);
      setState(() {
        session.rows = newRows;
        session.stagingBuffer = DataGridStagingBuffer(
          columns: session.columns,
          rows: session.rows,
          primaryKeys: session.resultGridPrimaryKeys,
        );
        session.savingChanges = false;
      });
    } catch (e) {
      if (mounted) {
        invalidatePane(session);
        setState(() => session.savingChanges = false);
        await showTableViewSaveFailedDialog(context: context, error: e);
      }
    }
  }

  Future<void> openSqlFile() async {
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
        session.markSaved(newFilePath: file.path);
        invalidatePane(session);
        setState(() {});
      } else {
        addNewTab(initialSql: text, title: file.name, filePath: file.path);
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

  Future<void> saveSqlFile() async {
    try {
      final session = _activeSession;
      final existingPath = session.filePath;
      if (existingPath != null && existingPath.isNotEmpty) {
        await File(existingPath).writeAsString(session.controller.text);
        session.markSaved();
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
      invalidatePane(session);
      setState(() {
        session.title = File(path).uri.pathSegments.last;
        session.markSaved(newFilePath: path);
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

  @override
  material.Widget build(material.BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        NewSqlIntent: CallbackAction<NewSqlIntent>(
          onInvoke: (intent) {
            addNewTab();
            return null;
          },
        ),
        CloseSqlTabIntent: CallbackAction<CloseSqlTabIntent>(
          onInvoke: (intent) {
            if (_sessions.length > 1) {
              unawaited(closeTab(_activeSessionIndex));
            }
            return null;
          },
        ),
        NextSqlTabIntent: CallbackAction<NextSqlTabIntent>(
          onInvoke: (intent) {
            nextTab();
            return null;
          },
        ),
        PrevSqlTabIntent: CallbackAction<PrevSqlTabIntent>(
          onInvoke: (intent) {
            prevTab();
            return null;
          },
        ),
        OpenSqlIntent: CallbackAction<OpenSqlIntent>(
          onInvoke: (intent) {
            unawaited(openSqlFile());
            return null;
          },
        ),
        SaveSqlIntent: CallbackAction<SaveSqlIntent>(
          onInvoke: (intent) {
            unawaited(saveSqlFile());
            return null;
          },
        ),
      },
      child: material.CallbackShortcuts(
        bindings: {
          const material.SingleActivator(LogicalKeyboardKey.keyT, control: true): addNewTab,
          const material.SingleActivator(LogicalKeyboardKey.keyT, meta: true): addNewTab,
          const material.SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
            if (_sessions.length > 1) unawaited(closeTab(_activeSessionIndex));
          },
          const material.SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
            if (_sessions.length > 1) unawaited(closeTab(_activeSessionIndex));
          },
          const material.SingleActivator(LogicalKeyboardKey.tab, control: true): nextTab,
          const material.SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): prevTab,
          const material.SingleActivator(LogicalKeyboardKey.f5): () {
            if (!_activeSession.running) unawaited(execute(_activeSession));
          },
          const material.SingleActivator(LogicalKeyboardKey.enter, control: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession));
          },
          const material.SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession));
          },
          const material.SingleActivator(LogicalKeyboardKey.numpadEnter, control: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession));
          },
          const material.SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession));
          },
          const material.SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession));
          },
          const material.SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession));
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
                onAdd: addNewTab,
                onClose: _sessions.length > 1
                    ? (index) => unawaited(closeTab(index))
                    : null,
              ),
              material.Expanded(
                child: material.IndexedStack(
                  index: _activeSessionIndex,
                  children: [
                    for (final session in _sessions)
                      _paneCache.putIfAbsent(
                        session.id,
                        () => _buildSessionPane(context, session),
                      ),
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
    paneBuildCount++;
    if (session.isDiagram) {
      return ErdView(
        key: material.ValueKey(session.id),
        delegate: widget.delegate,
        dialect: widget.dialect,
        onOpenTable: _openTableFromDiagram,
      );
    }
    final theme = Theme.of(context);
    final accent = context.workbench.accent;

    return VerticalSplitPane(
      key: material.ValueKey(session.id),
      fraction: session.topFraction,
      maxFraction: 0.85,
      top: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          material.Container(
            padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: SqlEditorChrome.sqlToolbarDecoration(context),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: material.WrapCrossAlignment.center,
                  children: [
                    if (widget.headerBadge != null)
                      widget.headerBadge!
                    else
                      const Text('Query').semiBold().small(),
                    if (effectiveDatabase.isNotEmpty)
                      Text('DB: $effectiveDatabase').muted().small(),
                    if (widget.delegate.supportsTransactions)
                      Text(_txLabel()).muted().small(),
                    OutlineButton(
                      size: ButtonSize.small,
                      onPressed: widget.connectionRow.id != null && !session.running
                          ? () {
                              showSqlQueryHistoryDialog(
                                context: context,
                                connectionId: widget.connectionRow.id!,
                                databaseName: effectiveDatabase,
                                sqlController: session.controller,
                                onOpenInNewTab: (sql) => addNewTab(initialSql: sql),
                              );
                            }
                          : null,
                      leading: material.Icon(
                        material.Icons.history_rounded,
                        size: 16,
                        color: accent,
                      ),
                      child: const Text('History'),
                    ),
                    OutlineButton(
                      onPressed: session.running ? null : () => execute(session),
                      leading: session.running
                          ? QueryaSpinner(
                              size: QueryaSpinnerSize.sm,
                              color: accent,
                            )
                          : material.Icon(
                              material.Icons.play_arrow_rounded,
                              size: 18,
                              color: accent,
                            ),
                      child: const Text('Execute (F5)'),
                    ),
                    OutlineButton(
                      key: const material.ValueKey('open_diagram_tab'),
                      onPressed: openDiagramTab,
                      child: const Text('Diagram'),
                    ),
                    if (widget.extraToolbarTrailing?.call(context, session) case final extra?)
                      extra,
                  ],
                ),
                if (widget.supportsAutocommit || widget.supportsStmtTimeout || widget.delegate.supportsTransactions) ...[
                  const Gap(8),
                  material.Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: material.WrapCrossAlignment.center,
                    children: [
                      if (widget.supportsAutocommit) ...[
                        material.Row(
                          mainAxisSize: material.MainAxisSize.min,
                          children: [
                            const Text('Autocommit').small(),
                            const Gap(6),
                            material.Switch(
                              value: _autocommit,
                              onChanged: session.running
                                  ? null
                                  : (v) {
                                      invalidateAllPanes();
                                      setState(() => _autocommit = v);
                                      widget.onAutocommitChanged?.call(v);
                                    },
                            ),
                          ],
                        ),
                      ],
                      if (widget.supportsStmtTimeout) ...[
                        material.Row(
                          mainAxisSize: material.MainAxisSize.min,
                          children: [
                            const Text('Stmt timeout').small(),
                            const Gap(6),
                            SqlStatementTimeoutDropdown(
                              value: _queryTimeoutSeconds,
                              onChanged: _onStmtTimeoutChanged,
                              enabled: !session.running,
                            ),
                            const Gap(4),
                            IconButton.ghost(
                              onPressed: session.running ? null : () => showPreferencesDialog(context),
                              icon: material.Icon(
                                material.Icons.settings_rounded,
                                size: 20,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.delegate.supportsTransactions) ...[
                        OutlineButton(
                          onPressed: session.running ? null : () => runTxCommand('BEGIN'),
                          child: const Text('Begin'),
                        ),
                        OutlineButton(
                          onPressed: session.running ? null : () => runTxCommand('COMMIT'),
                          child: const Text('Commit'),
                        ),
                        OutlineButton(
                          onPressed: session.running ? null : () => runTxCommand('ROLLBACK'),
                          child: const Text('Rollback'),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
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
            padding: const material.EdgeInsets.symmetric(horizontal: 12),
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
              columnDataTypes: session.resultGridColumnDataTypes,
              onApplyChanges: widget.isReadOnly ||
                      !sqlResultGridSaveEnabled(
                        sql: session.lastExecutedSql,
                        resultColumns: session.columns,
                        primaryKeys: session.resultGridPrimaryKeys,
                      )
                  ? null
                  : () => applyStagedChanges(session),
              isSaving: session.savingChanges,
              errorAction: widget.errorActionBuilder?.call(context, session),
            ),
          ),
        ],
      ),
    );
  }

  String _txLabel() {
    if (_txOpen == null) return 'Transaction: —';
    return _txOpen! ? 'Transaction: open' : 'Transaction: none';
  }
}
