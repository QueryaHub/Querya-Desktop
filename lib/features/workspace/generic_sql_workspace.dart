import 'package:querya_desktop/core/database/statement_queue.dart';
import 'package:querya_desktop/core/database/sql_statement_splitter.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:file_selector/file_selector.dart';
import 'package:querya_desktop/core/storage/mutation_audit_recorder.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/actions/table_view_command_bridge.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/core/erd/erd_table_names.dart';
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
import 'package:querya_desktop/features/workspace/plan_tree_view.dart';
import 'package:querya_desktop/features/workspace/query_plan.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:querya_desktop/features/workspace/sql_query_history_dialog.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_bar.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_session.dart';
import 'package:querya_desktop/features/workspace/sql_result_grid_schema.dart';
import 'package:querya_desktop/features/workspace/table_view_staging.dart';
import 'package:querya_desktop/shared/widgets/querya_action_menu.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Reusable base SQL workspace supporting multi-tab editing, statement execution,
/// destructive query confirmations, unsaved changes guards, DML staging and result grids.
/// Entries of the Session menu in the SQL toolbar.
sealed class _SessionChoice {
  const _SessionChoice();
}

class _ToggleAutocommit extends _SessionChoice {
  const _ToggleAutocommit();
}

class _SetTimeout extends _SessionChoice {
  const _SetTimeout(this.seconds);
  final int? seconds;
}

class _BeginTransaction extends _SessionChoice {
  const _BeginTransaction();
}

class _OpenPreferences extends _SessionChoice {
  const _OpenPreferences();
}

class GenericSqlWorkspace extends material.StatefulWidget {
  const GenericSqlWorkspace({
    super.key,
    required this.connectionRow,
    required this.delegate,
    this.catalogDelegateFactory,
    required this.dialect,
    this.sessionPrefix = 'query',
    this.initialSql,
    this.initialTabTitle,
    this.transactionOpenNotifier,
    this.isReadOnly = false,
    this.showDiagram = true,
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

  /// Makes the session the schema diagram reads the catalog through. Without
  /// one, the diagram uses [delegate] (no workspace does that today). The
  /// editor's own session keeps its transaction and its running query.
  final SqlExecutionDelegate Function()? catalogDelegateFactory;
  final SqlDialect dialect;
  final String sessionPrefix;
  final String? initialSql;
  final String? initialTabTitle;
  final material.ValueNotifier<bool?>? transactionOpenNotifier;
  final bool isReadOnly;

  /// Whether the Diagram tab is offered. Extension drivers have no diagram
  /// source yet, so their workspace turns it off.
  final bool showDiagram;

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

  SqlExecutionDelegate? _catalogDelegate;

  SqlExecutionDelegate get _diagramDelegate {
    final factory = widget.catalogDelegateFactory;
    if (factory == null) return widget.delegate;
    return _catalogDelegate ??= factory();
  }

  @override
  void dispose() {
    _catalogDelegate?.dispose();
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

  void _formatActive() {
    if (_activeSession.running) return;
    _activeSession.formatSql();
    invalidatePane(_activeSession);
    setState(() {});
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
      onExecuteStatement: () {
        if (!_activeSession.running) {
          unawaited(execute(_activeSession, true));
        }
      },
      onCloseTab: () {
        if (_sessions.length > 1) unawaited(closeTab(_activeSessionIndex));
      },
      onNextTab: nextTab,
      onPrevTab: prevTab,
      onFormat: _formatActive,
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

  /// Double click or "Open data" on a diagram card: the table browser, as the
  /// Quick Switcher opens it. With [relations] it starts in the Relations
  /// view. Without the app shell (tests, embedded use) the rows open in a
  /// new SQL tab instead.
  void _openTableFromDiagram(String table, {bool relations = false}) {
    final open = QueryaCommandHost.maybeOf(context)?.onOpenSchemaObject;
    if (open == null) {
      _openTableInSql(table);
      return;
    }
    if (relations) TableViewCommandBridge.instance.requestViewForNextTable(1);
    open(ErdTableNames.schemaObject(table, widget.dialect,
        database: effectiveDatabase));
  }

  /// "Open in SQL" on a diagram card: `SELECT * … LIMIT 100` in a new tab,
  /// with the name qualified and quoted for the dialect.
  void _openTableInSql(String table) {
    final (_, bare) = ErdTableNames.split(table, widget.dialect);
    addNewTab(
      initialSql: ErdTableNames.selectSql(table, widget.dialect),
      title: bare,
    );
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
    // The transaction label lives in each pane: rebuild the cached panes only
    // when the state really changed, not after every statement.
    if (mounted && v != _txOpen) {
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
          session.error = statementTimeoutText(e);
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

  /// Runs the selection, else the whole text. With [statementAtCursor] (run
  /// statement) only the statement under the caret, see [SqlStatementSplitter].
  List<QueryaActionMenuItem<_SessionChoice>> _sessionMenuItems() => [
        if (widget.supportsAutocommit)
          QueryaActionMenuItem(
            value: const _ToggleAutocommit(),
            label: _autocommit ? 'Autocommit: on' : 'Autocommit: off',
          ),
        if (widget.supportsStmtTimeout)
          for (final option in kSqlStatementTimeoutMenuItems)
            QueryaActionMenuItem(
              value: _SetTimeout(option.value),
              label: 'Timeout: ${option.label}'
                  '${option.value == _queryTimeoutSeconds ? '  ✓' : ''}',
            ),
        if (widget.delegate.supportsTransactions && _txOpen != true)
          const QueryaActionMenuItem(
            value: _BeginTransaction(),
            label: 'Begin transaction',
          ),
        const QueryaActionMenuItem(
          value: _OpenPreferences(),
          label: 'Preferences…',
        ),
      ];

  void _onSessionChoice(_SessionChoice choice) {
    switch (choice) {
      case _ToggleAutocommit():
        invalidateAllPanes();
        setState(() => _autocommit = !_autocommit);
        widget.onAutocommitChanged?.call(_autocommit);
      case _SetTimeout(:final seconds):
        _onStmtTimeoutChanged(seconds);
      case _BeginTransaction():
        unawaited(runTxCommand('BEGIN'));
      case _OpenPreferences():
        showPreferencesDialog(context);
    }
  }

  final Map<String, SqlResultGridSchema> _gridSchemaCache = {};

  /// Table schemas are cached per (database, schema, table), so any query on a
  /// table reuses the lookup, not only the same text. A query with no single
  /// target table is not cached.
  String? _schemaCacheKey(String sql) {
    final target = SqlTableTargetExtractor.extract(sql);
    if (target == null) return null;
    return '$effectiveDatabase\u0001${target.schema ?? ''}\u0001'
        '${target.tableName}';
  }

  static final _readQueryRegex = RegExp(
    r'^\s*(select|with|values|show|explain|pragma|describe)\b',
    caseSensitive: false,
  );

  static bool _isReadQuery(String sql) => _readQueryRegex.hasMatch(sql);

  String _resultStatus(
    SqlExecutionResult result,
    List<String> cols,
    List<List<String>> outRows,
    String? editHint,
  ) {
    if (result.statusMessage != null) {
      return withEditHint(result.statusMessage!, editHint);
    }
    if (cols.isEmpty && outRows.isEmpty) {
      return result.affectedRows != null
          ? 'OK. Rows affected: ${result.affectedRows}.'
          : 'Command completed.';
    }
    final cap = _resultMaxRows;
    return withEditHint(
      result.isTruncated
          ? 'Showing first $cap row(s) (result capped).'
          : '${outRows.length} row(s).',
      editHint,
    );
  }

  /// Applies the table schema to the result it was asked for. An answer that
  /// arrives after the tab has moved on to another result is dropped.
  void _applyGridSchema(
    SqlQueryTabSession session,
    String userSql,
    List<String> cols,
    List<List<String>> outRows,
    SqlResultGridSchema gridSchema,
    SqlExecutionResult result,
    String? scriptStatus,
  ) {
    if (!mounted ||
        !identical(session.rows, outRows) ||
        session.lastExecutedSql != userSql) {
      return;
    }
    final pks = gridSchema.primaryKeys;
    final editHint = gridSchema.editHint(cols);
    final canSave = sqlResultGridSaveEnabled(
      sql: userSql,
      resultColumns: cols,
      primaryKeys: pks,
    );
    setState(() {
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
      session.statusLine = scriptStatus != null
          ? withEditHint(scriptStatus, editHint)
          : _resultStatus(result, cols, outRows, editHint);
    });
  }

  /// Runs the statement at the caret ([statementAtCursor]: the selection, or
  /// the one statement under the caret), or else the script: the selection, or
  /// the whole text. A script runs one statement at a time and stops at the
  /// first error.
  Future<void> execute([
    SqlQueryTabSession? targetSession,
    bool statementAtCursor = false,
  ]) async {
    final session = targetSession ?? _activeSession;
    if (session.running) return;

    final selection = session.controller.selection;
    final text = session.controller.text;
    final selected = selection.isValid && !selection.isCollapsed;
    final scope = selected ? selection.textInside(text) : text;
    final spans = _runSpans(
      scope,
      statementAtCursor: statementAtCursor,
      selected: selected,
      caret: selection.isValid ? selection.baseOffset : scope.length,
    );
    if (spans.isEmpty) return;
    final scopeStart = selected ? selection.start : 0;
    final texts = [for (final s in spans) s.textIn(scope)];
    final runSql = statementAtCursor ? texts.single : scope.trim();
    // One statement goes to the driver as the run text, with its ';' when the
    // whole script is one statement.
    final sent = texts.length == 1 ? [runSql] : texts;

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

    // Checked once, over the text that will run.
    final confirmDestructive =
        await AppSettings.instance.getConfirmDestructiveOperations();
    if (confirmDestructive) {
      final inspection = DestructiveSqlDetector.inspect(runSql);
      if (inspection.isDestructive) {
        if (!mounted) return;
        final confirmed = await showDestructiveQueryDialog(
          context: context,
          result: inspection,
          sql: runSql,
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
      session.elapsed = null;
      session.planRoot = null;
      session.resultGridPrimaryKeys = const [];
      session.resultGridColumnDataTypes = null;
      session.resultGridColumnMeta = null;
    });
    QueryaShellStatus.instance.beginBusy(message: 'Running query…');
    final sw = Stopwatch()..start();

    // The grid shows the last statement that returned columns, or else the
    // last statement.
    SqlExecutionResult? shown;
    var shownIndex = 0;
    var affectedTotal = 0;
    var affectedKnown = false;
    String? failure;
    var failedAt = 0;
    try {
      for (var i = 0; i < texts.length; i++) {
        final SqlExecutionResult result;
        try {
          result = await widget.delegate.executeQuery(
            sent[i],
            limit: _resultMaxRows,
            timeout: statementTimeout,
          );
        } catch (e) {
          // A single statement reports its error as before.
          if (texts.length == 1) rethrow;
          failure = _runErrorText(e);
          failedAt = i;
          break;
        }
        if (!mounted) return;
        if (result.affectedRows != null) {
          affectedTotal += result.affectedRows!;
          affectedKnown = true;
        }
        if (shown == null ||
            result.columns.isNotEmpty ||
            shown.columns.isEmpty) {
          shown = result;
          shownIndex = i;
        }
        auditSqlExecution(
          connection: widget.connectionRow,
          databaseName: effectiveDatabase,
          sql: sent[i],
          rowsAffected: result.affectedRows,
          source: MutationAuditSource.sqlEditor,
        );
      }
      if (!mounted) return;

      if (failure != null) {
        final at = scopeStart + spans[failedAt].start;
        final line = 1 + '\n'.allMatches(text.substring(0, at)).length;
        session.controller.selection =
            material.TextSelection.collapsed(offset: at);
        invalidatePane(session);
        setState(() {
          session.error =
              'Statement ${failedAt + 1} of ${texts.length} failed (line $line): $failure';
          session.running = false;
        });
        QueryaShellStatus.instance.endBusy();
        return;
      }

      final result = shown!;
      final cols = result.columns;
      final outRows = result.rows;
      final shownSql = sent[shownIndex];
      final multi = texts.length > 1;
      final scriptStatus = multi
          ? '${texts.length} statements'
              '${affectedKnown ? ' · $affectedTotal rows affected' : ''}'
          : null;

      // Rows show now. The table schema (keys, types, edit hint) follows: from
      // the cache, or from the delegate in the background.
      final cacheKey = _schemaCacheKey(shownSql);
      final cached = cacheKey == null ? null : _gridSchemaCache[cacheKey];
      invalidatePane(session);
      setState(() {
        session.columns = cols;
        session.rows = outRows;
        session.affectedRows = affectedKnown ? affectedTotal : null;
        session.lastExecutedSql = shownSql;
        session.resultGridPrimaryKeys = const [];
        session.resultGridColumnDataTypes = null;
        session.resultGridColumnMeta = null;
        session.stagingBuffer?.dispose();
        session.stagingBuffer = null;
        session.statusLine = scriptStatus ??
            _resultStatus(result, cols, outRows, null);
        session.elapsed = multi ? sw.elapsed : result.elapsed ?? sw.elapsed;
        session.running = false;
      });
      // Anything that is not a read may change table shapes: forget the cache.
      if (!sent.every(_isReadQuery)) _gridSchemaCache.clear();

      if (cached != null) {
        _applyGridSchema(
            session, shownSql, cols, outRows, cached, result, scriptStatus);
      } else {
        unawaited(
          widget.delegate.resolveTableSchema(shownSql, cols).then(
            (gridSchema) {
              if (!mounted) return;
              // A result with no columns gets no schema from the delegate, so
              // it is not worth keeping for the table.
              if (cacheKey != null && cols.isNotEmpty) {
                _gridSchemaCache[cacheKey] = gridSchema;
              }
              _applyGridSchema(session, shownSql, cols, outRows, gridSchema,
                  result, scriptStatus);
            },
            onError: (_) {}, // The rows stay without save.
          ),
        );
      }

      sw.stop();
      final duration = multi ? sw.elapsed : result.elapsed ?? sw.elapsed;
      QueryaShellStatus.instance.reportQueryResult(
        duration: duration,
        rowCount: outRows.length,
        columnCount: cols.length,
        message: session.statusLine,
      );

      // One history entry per run, with the text that ran.
      final cid = widget.connectionRow.id;
      if (cid != null) {
        unawaited(
          LocalDb.instance.recordSqlQueryHistory(
            connectionId: cid,
            databaseName: effectiveDatabase,
            sqlText: runSql,
            maxEntries: _historyMaxEntries,
          ),
        );
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        invalidatePane(session);
        setState(() {
          session.error = statementTimeoutText(e);
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
      // Autocommit: after a read that succeeded while no transaction is known
      // to be open, none can have been opened, so the server is not asked.
      final afterPlainRead = _autocommit &&
          session.error == null &&
          _txOpen == false &&
          sent.every(_isReadQuery);
      if (!afterPlainRead) await refreshTxStatus();
    }
  }

  /// Shortcut prefix shown in the run menu: ⌘ on macOS, Ctrl elsewhere.
  static String get _modLabel => Platform.isMacOS ? '⌘' : 'Ctrl+';

  void _openHistory(SqlQueryTabSession session) {
    final cid = widget.connectionRow.id;
    if (cid == null || session.running) return;
    showSqlQueryHistoryDialog(
      context: context,
      connectionId: cid,
      databaseName: effectiveDatabase,
      sqlController: session.controller,
      onOpenInNewTab: (sql) => addNewTab(initialSql: sql),
    );
  }

  /// The ranges of [scope] a run covers. A caret run takes the statement at
  /// [caret]; a selected caret run is the selection as one statement; a script
  /// is every statement.
  static List<SqlStatementSpan> _runSpans(
    String scope, {
    required bool statementAtCursor,
    required bool selected,
    required int caret,
  }) {
    if (statementAtCursor && selected) {
      final start = scope.length - scope.trimLeft().length;
      final end = scope.trimRight().length;
      return end > start
          ? [SqlStatementSpan(start: start, end: end, line: 1)]
          : const [];
    }
    final all = SqlStatementSplitter.spans(scope);
    if (!statementAtCursor) return all;
    final at = SqlStatementSplitter.at(all, caret);
    return at == null ? const [] : [at];
  }

  static String _runErrorText(Object e) =>
      statementTimeoutText(e) ?? e.toString();

  /// Shows the query plan of the selection (or the whole editor text) in the
  /// result grid, one plan line per row.
  /// The plan as a tree; null when the driver has none or it cannot be read.
  /// The text plan is already shown, so a failure here is not an error.
  Future<PlanNode?> _explainTreeOrNull(String sql) async {
    try {
      return await widget.delegate.explainTree(sql);
    } catch (_) {
      return null;
    }
  }

  Future<void> explain([SqlQueryTabSession? targetSession]) async {
    final session = targetSession ?? _activeSession;
    if (session.running || !widget.delegate.supportsExplain) return;

    final selection = session.controller.selection;
    final sql = (selection.isValid && !selection.isCollapsed
            ? selection.textInside(session.controller.text)
            : session.controller.text)
        .trim();
    if (sql.isEmpty) return;

    invalidatePane(session);
    setState(() {
      session.running = true;
      session.error = null;
      session.columns = [];
      session.rows = [];
      session.affectedRows = null;
      session.statusLine = null;
      session.elapsed = null;
      session.planRoot = null;
      session.resultGridPrimaryKeys = const [];
      session.resultGridColumnDataTypes = null;
      session.resultGridColumnMeta = null;
      session.stagingBuffer?.dispose();
      session.stagingBuffer = null;
    });
    QueryaShellStatus.instance.beginBusy(message: 'Explaining query…');
    try {
      final plan = await widget.delegate.explainQuery(sql);
      if (!mounted) return;
      final lines = plan.split('\n').where((l) => l.trim().isNotEmpty).toList();
      invalidatePane(session);
      setState(() {
        session.columns = const ['QUERY PLAN'];
        session.rows = [for (final l in lines) [l]];
        session.statusLine = 'Query plan: ${lines.length} line(s).';
        session.running = false;
      });
      final tree = await _explainTreeOrNull(sql);
      if (!mounted) return;
      setState(() => session.planRoot = tree);
    } catch (e) {
      if (mounted) {
        invalidatePane(session);
        setState(() {
          session.error = e.toString();
          session.running = false;
        });
      }
    } finally {
      QueryaShellStatus.instance.endBusy();
    }
  }

  /// Interrupts the statement that is running in [targetSession]. The pending
  /// `execute` / `explain` then finishes with the driver's cancellation error.
  Future<void> cancelRunning([SqlQueryTabSession? targetSession]) async {
    final session = targetSession ?? _activeSession;
    if (!session.running || !widget.delegate.supportsCancel) return;
    try {
      await widget.delegate.cancelQuery();
    } catch (e) {
      if (mounted) {
        invalidatePane(session);
        setState(() => session.error = 'Cancel failed: $e');
      }
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
            if (!_activeSession.running) unawaited(execute(_activeSession, true));
          },
          const material.SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession, true));
          },
          const material.SingleActivator(LogicalKeyboardKey.enter, control: true, shift: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession));
          },
          const material.SingleActivator(LogicalKeyboardKey.enter, meta: true, shift: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession));
          },
          const material.SingleActivator(LogicalKeyboardKey.numpadEnter, control: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession, true));
          },
          const material.SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession, true));
          },
          const material.SingleActivator(LogicalKeyboardKey.keyH, control: true): () => _openHistory(_activeSession),
          const material.SingleActivator(LogicalKeyboardKey.keyH, meta: true): () => _openHistory(_activeSession),
          const material.SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession, true));
          },
          const material.SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
            if (!_activeSession.running) unawaited(execute(_activeSession, true));
          },
          const material.SingleActivator(LogicalKeyboardKey.keyF, shift: true, alt: true):
              _formatActive,
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
                trailing: widget.showDiagram
                    ? QueryaActionButton(
                        key: const material.ValueKey('open_diagram_tab'),
                        label: 'Diagram',
                        icon: material.Icons.account_tree_outlined,
                        tooltip: 'Schema diagram',
                        onPressed: openDiagramTab,
                      )
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
        source: SqlErdSource(delegate: _diagramDelegate, dialect: widget.dialect),
        databaseName: effectiveDatabase,
        onOpenTable: _openTableFromDiagram,
        onOpenInSql: _openTableInSql,
        onShowRelations:
            QueryaCommandHost.maybeOf(context)?.onOpenSchemaObject == null
                ? null
                : (table) => _openTableFromDiagram(table, relations: true),
      );
    }

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
            child: _buildToolbarRow(context, session),
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
          if (session.planRoot != null)
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: material.Align(
                alignment: material.Alignment.centerLeft,
                child: material.SizedBox(
                  width: 200,
                  child: QueryaTabStrip(
                    labels: const ['Plan', 'Text'],
                    selectedIndex: session.planAsTree ? 0 : 1,
                    onSelected: (i) => setState(() => session.planAsTree = i == 0),
                  ),
                ),
              ),
            ),
          Expanded(
            child: session.planRoot != null && session.planAsTree
                ? PlanTreeView(root: session.planRoot!)
                : ResultsTab(
              columns: session.columns,
              rows: session.rows,
              errorMessage: session.error,
              isLoading: session.running,
              affectedRows: session.affectedRows,
              statusLine: session.statusLine,
              elapsed: session.elapsed,
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

  /// The toolbar in one row: Run and Explain, the editor tools, then the
  /// session state. On a narrow window it scrolls sideways instead of wrapping.
  material.Widget _buildToolbarRow(
    material.BuildContext context,
    SqlQueryTabSession session,
  ) {
    final accent = context.workbench.accent;
    final historyEnabled = widget.connectionRow.id != null && !session.running;
    return material.LayoutBuilder(
      builder: (context, constraints) {
        // Below the breakpoint the labels hide and the icons stay (the
        // tooltips name them), so the toolbar stays on one row.
        final compact = constraints.maxWidth < _toolbarCompactWidth;
        return material.SingleChildScrollView(
      scrollDirection: material.Axis.horizontal,
      child: material.Row(
        children: [
          if (widget.headerBadge != null) ...[
            widget.headerBadge!,
            const material.SizedBox(width: 12),
          ],
          QueryaActionButton(
            key: const material.ValueKey('run_script'),
            label: 'Execute (F5)',
            icon: material.Icons.play_arrow_rounded,
            compact: compact,
            loading: session.running,
            onPressed: () => execute(session),
          ),
          const material.SizedBox(width: 4),
          QueryaActionMenu<bool>(
            key: const material.ValueKey('run_menu'),
            items: [
              QueryaActionMenuItem(
                value: true,
                label: 'Run statement (${_modLabel}Enter)',
                icon: material.Icons.short_text_rounded,
              ),
              const QueryaActionMenuItem(
                value: false,
                label: 'Run script (F5)',
                icon: material.Icons.list_alt_rounded,
              ),
            ],
            onSelected: (atCursor) {
              if (!session.running) {
                unawaited(execute(session, atCursor));
              }
            },
            child: const material.Icon(
              material.Icons.expand_more_rounded,
              size: 16,
            ),
          ),
          if (widget.delegate.supportsExplain) ...[
            const material.SizedBox(width: 8),
            QueryaActionButton(
              key: const material.ValueKey('explain_query'),
              label: 'Explain',
              icon: material.Icons.account_tree_outlined,
            compact: compact,
              tooltip: 'Show the query plan',
              onPressed: session.running ? null : () => explain(session),
            ),
          ],
          if (session.running && widget.delegate.supportsCancel) ...[
            const material.SizedBox(width: 8),
            QueryaActionButton(
              key: const material.ValueKey('cancel_query'),
              label: 'Cancel',
              icon: material.Icons.stop_rounded,
            compact: compact,
              isDestructive: true,
              tooltip: 'Interrupt the running query',
              onPressed: () => cancelRunning(session),
            ),
          ],
          const material.SizedBox(width: 16),
          QueryaIconButton(
            key: const material.ValueKey('history_button'),
            icon: const material.Icon(material.Icons.history_rounded),
            tooltip: 'History (${_modLabel}H)',
            onPressed: historyEnabled ? () => _openHistory(session) : null,
          ),
          QueryaIconButton(
            key: const material.ValueKey('format_button'),
            icon: const material.Icon(material.Icons.auto_fix_high_rounded),
            tooltip: 'Format (Shift+Alt+F)',
            onPressed: session.running ? null : () => session.formatSql(),
          ),
          QueryaIconButton(
            key: const material.ValueKey('open_sql_button'),
            icon: const material.Icon(material.Icons.folder_open_outlined),
            tooltip: 'Open .sql file',
            onPressed: () => unawaited(openSqlFile()),
          ),
          QueryaIconButton(
            key: const material.ValueKey('save_sql_button'),
            icon: const material.Icon(material.Icons.save_outlined),
            tooltip: 'Save .sql file',
            onPressed: () => unawaited(saveSqlFile()),
          ),
          const material.SizedBox(width: 16),
          if (effectiveDatabase.isNotEmpty) ...[
            QueryaBadge.status(
              effectiveDatabase,
              status: QueryaBadgeStatus.neutral,
            ),
            const material.SizedBox(width: 8),
          ],
          if (widget.delegate.supportsTransactions) ...[
            _txBadge(),
            if (_txOpen == true) ...[
              const material.SizedBox(width: 8),
              QueryaActionButton(
                label: 'Commit',
                onPressed:
                    session.running ? null : () => runTxCommand('COMMIT'),
              ),
              const material.SizedBox(width: 4),
              QueryaActionButton(
                label: 'Rollback',
                onPressed:
                    session.running ? null : () => runTxCommand('ROLLBACK'),
              ),
            ],
            const material.SizedBox(width: 8),
          ],
          // Autocommit, statement timeout, Begin and Preferences live in one
          // Session menu.
          material.IgnorePointer(
            ignoring: session.running,
            child: material.Opacity(
              opacity: session.running ? 0.5 : 1,
              child: QueryaActionMenu<_SessionChoice>(
                key: const material.ValueKey('session_menu'),
                items: _sessionMenuItems(),
                onSelected: (choice) => _onSessionChoice(choice),
                child: material.Padding(
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: material.Row(
                    mainAxisSize: material.MainAxisSize.min,
                    children: [
                      material.Icon(material.Icons.tune_rounded,
                          size: 16, color: accent),
                      const material.SizedBox(width: 6),
                      if (!compact) ...[
                        Text(_autocommit
                            ? 'Session · auto-commit'
                            : 'Session · manual'),
                        const material.SizedBox(width: 4),
                      ],
                      material.Icon(material.Icons.expand_more_rounded,
                          size: 16, color: accent),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.extraToolbarTrailing?.call(context, session) case final extra?) ...[
            const material.SizedBox(width: 8),
            extra,
          ],
        ],
      ),
    );
      },
    );
  }

  /// Toolbar width below which button labels hide and only icons stay.
  static const double _toolbarCompactWidth = 900;

  /// Transaction state as a badge: an open transaction is a warning, because
  /// work can be lost, and looks different from no transaction.
  material.Widget _txBadge() {
    final open = _txOpen;
    if (open == null) {
      return const QueryaBadge.status('Transaction —', status: QueryaBadgeStatus.neutral);
    }
    if (open) {
      return const QueryaBadge.status('Transaction open', status: QueryaBadgeStatus.warning);
    }
    return QueryaBadge.status(
      _autocommit ? 'Auto-commit' : 'Manual commit',
      status: _autocommit ? QueryaBadgeStatus.neutral : QueryaBadgeStatus.info,
    );
  }
}
