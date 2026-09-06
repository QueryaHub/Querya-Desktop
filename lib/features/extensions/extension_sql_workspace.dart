import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:file_selector/file_selector.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/layout/vertical_split_pane.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/extensions/extension_driver_recovery_banner.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Table/view selected in the sidebar tree of an extension connection.
typedef ExtensionSelectedObject = ({String database, String name});

/// Ad-hoc SQL editor + results for extension database drivers (Block D).
///
/// Executes queries through [ExtensionDriverSession] (`db.query` JSON-RPC).
/// When [selectedObject] is set, seeds and auto-runs a preview query so
/// clicking a table in the sidebar opens its data.
class ExtensionSqlWorkspace extends material.StatefulWidget {
  const ExtensionSqlWorkspace({
    super.key,
    required this.connectionRow,
    this.selectedObject,
    this.initialSql,
  });

  final ConnectionRow connectionRow;
  final ExtensionSelectedObject? selectedObject;
  final String? initialSql;

  @override
  material.State<ExtensionSqlWorkspace> createState() =>
      _ExtensionSqlWorkspaceState();
}

class _ExtensionSqlWorkspaceState
    extends material.State<ExtensionSqlWorkspace> {
  final List<SqlQueryTabSession> _sessions = [];
  int _activeSessionIndex = 0;
  int _nextSessionId = 1;

  SqlQueryTabSession get _activeSession => _sessions[_activeSessionIndex];

  bool _restartingDriver = false;

  int _historyMaxEntries = kDefaultSqlHistoryMaxEntries;
  int _resultMaxRows = kDefaultSqlResultMaxRows;
  double _editorFontSize = kDefaultSqlEditorFontSize;

  static const _previewRowLimit = 200;

  bool _isDriverError(String? err) {
    if (err == null) return false;
    return err.contains('PluginCrashedException') ||
        err.contains('PluginDeadlockException') ||
        err.contains('PluginProtocolTimeoutException') ||
        err.contains('TimeoutException') ||
        err.contains('SocketException') ||
        err.contains('Broken pipe') ||
        err.contains('JsonRpcStdioClient') ||
        err.contains('Connection') ||
        err.contains('is not started');
  }

  Future<void> _restartDriver() async {
    if (_restartingDriver) return;
    setState(() {
      _restartingDriver = true;
    });
    try {
      await ExtensionDriverSession.instance.restart(widget.connectionRow);
      if (!mounted) return;
      showAppToast(
        context: context,
        message: 'Driver restarted successfully',
        variant: AppToastVariant.success,
      );
      setState(() {
        _restartingDriver = false;
        _activeSession.error = null;
      });
      await _execute(_activeSession);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activeSession.error = 'Driver restart failed: $e';
        _restartingDriver = false;
      });
      showAppToast(
        context: context,
        message: 'Driver restart failed: $e',
        variant: AppToastVariant.error,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _sessions.add(
      SqlQueryTabSession(
        id: 'ext_tab_1',
        title: widget.selectedObject?.name ?? 'Query 1',
        initialSql: widget.initialSql,
      ),
    );
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadWorkspaceSettings());
      _applySelectedObject();
      _registerSqlEditorCommands();
    });
  }

  @override
  void dispose() {
    SqlEditorCommandBridge.instance
        .unregister(connectionId: widget.connectionRow.id);
    for (final s in _sessions) {
      s.dispose();
    }
    _sessions.clear();
    super.dispose();
  }

  void _registerSqlEditorCommands() {
    if (!mounted) return;
    SqlEditorCommandBridge.instance.register(
      connectionId: widget.connectionRow.id,
      onNew: _addNewTab,
      onOpen: () => unawaited(_openSqlFile()),
      onSave: () => unawaited(_saveSqlFile()),
      onCloseTab: () {
        if (_sessions.length > 1) {
          unawaited(_closeTab(_activeSessionIndex));
        }
      },
      onNextTab: _nextTab,
      onPrevTab: _prevTab,
      onExecute: () {
        if (!_activeSession.running) unawaited(_execute(_activeSession));
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
          setState(() {});
        } else {
          _addNewTab(initialSql: sql, title: title, filePath: filePath);
        }
      },
    );
  }

  void _addNewTab({String? initialSql, String? title, String? filePath}) {
    setState(() {
      _nextSessionId++;
      final session = SqlQueryTabSession(
        id: 'ext_tab_$_nextSessionId',
        title: title ?? 'Query $_nextSessionId',
        initialSql: initialSql,
        filePath: filePath,
        initialFraction:
            _sessions.isNotEmpty ? _activeSession.topFraction.value : 0.6,
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
  void didUpdateWidget(covariant ExtensionSqlWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final obj = widget.selectedObject;
    final old = oldWidget.selectedObject;
    final changed = obj != null &&
        (old == null || old.database != obj.database || old.name != obj.name);
    if (changed) {
      _applySelectedObject();
    }
  }

  void _applySelectedObject() {
    final obj = widget.selectedObject;
    if (obj == null) return;
    final sql =
        'SELECT * FROM `${obj.database}`.`${obj.name}` LIMIT $_previewRowLimit';
    if (_activeSession.controller.text.trim().isEmpty &&
        _activeSession.rows.isEmpty) {
      _activeSession.controller.value = material.TextEditingValue(
        text: sql,
        selection: material.TextSelection.collapsed(offset: sql.length),
      );
      _activeSession.title = obj.name;
      setState(() {});
      unawaited(_execute(_activeSession));
    } else {
      _addNewTab(initialSql: sql, title: obj.name);
      unawaited(_execute(_activeSession));
    }
  }

  Future<void> _loadWorkspaceSettings() async {
    final hist = await AppSettings.instance.getSqlHistoryMaxEntries();
    final rows = await AppSettings.instance.getSqlResultMaxRows();
    final font = await AppSettings.instance.getSqlEditorFontSize();
    if (!mounted) return;
    setState(() {
      _historyMaxEntries = hist;
      _resultMaxRows = rows;
      _editorFontSize = font;
    });
  }

  Future<void> _execute([SqlQueryTabSession? targetSession]) async {
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
      session.statusLine = null;
    });

    try {
      final result = await ExtensionDriverSession.instance.query(
        widget.connectionRow,
        userSql,
        limit: _resultMaxRows,
      );
      if (!mounted) return;

      setState(() {
        session.columns = result.columns;
        session.rows = result.rows;
        if (result.columns.isEmpty && result.rows.isEmpty) {
          session.statusLine = result.message ?? 'Command completed.';
        } else {
          final elapsed =
              result.elapsedMs != null ? ' in ${result.elapsedMs}ms' : '';
          final capped = result.rows.length >= _resultMaxRows;
          session.statusLine = capped
              ? 'Showing first $_resultMaxRows row(s)$elapsed (result capped).'
              : '${result.rows.length} row(s)$elapsed.';
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
    } catch (e) {
      if (mounted) {
        setState(() {
          session.error = e.toString();
          session.running = false;
        });
      }
    }
  }

  Future<void> _openSqlFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'SQL query', extensions: ['sql']),
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
      top: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _ExtensionSqlToolbar(
            connectionName: widget.connectionRow.name,
            onExecute: session.running ? null : () => unawaited(_execute(session)),
            running: session.running,
            isRestarting: _restartingDriver,
            onRestartDriver:
                session.running ? null : () => unawaited(_restartDriver()),
            onOpenSqlFile: () => unawaited(_openSqlFile()),
            onSaveSqlFile: () => unawaited(_saveSqlFile()),
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
          ),
          const Divider(height: 1),
          material.Expanded(
            child: QueryEditorTab(
              controller: session.controller,
              fontSize: _editorFontSize,
            ),
          ),
        ],
      ),
      bottom: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
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
          material.Expanded(
            child: ResultsTab(
              columns: session.columns,
              rows: session.rows,
              errorMessage: session.error,
              isLoading: session.running,
              statusLine: session.statusLine,
              errorAction: _isDriverError(session.error)
                  ? ExtensionDriverRecoveryBanner(
                      onRestart: () => unawaited(_restartDriver()),
                      isRestarting: _restartingDriver,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtensionSqlToolbar extends material.StatelessWidget {
  const _ExtensionSqlToolbar({
    required this.connectionName,
    required this.onExecute,
    required this.running,
    required this.onOpenSqlFile,
    required this.onSaveSqlFile,
    this.onOpenHistory,
    this.onRestartDriver,
    this.isRestarting = false,
  });

  final String connectionName;
  final VoidCallback? onExecute;
  final bool running;
  final VoidCallback onOpenSqlFile;
  final VoidCallback onSaveSqlFile;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onRestartDriver;
  final bool isRestarting;

  @override
  material.Widget build(material.BuildContext context) {
    final accent = context.workbench.accent;
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: SqlEditorChrome.sqlToolbarDecoration(context),
      child: material.Row(
        children: [
          material.Flexible(
            child: Text('Query · $connectionName').semiBold().small(),
          ),
          const Spacer(),
          if (onRestartDriver != null) ...[
            IconButton.ghost(
              onPressed: running || isRestarting ? null : onRestartDriver,
              icon: isRestarting
                  ? material.SizedBox(
                      width: 14,
                      height: 14,
                      child: material.CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  : material.Icon(
                      material.Icons.restart_alt_rounded,
                      size: 18,
                      color: accent,
                    ),
            ),
            const Gap(4),
          ],
          IconButton.ghost(
            onPressed: running ? null : onOpenSqlFile,
            icon: material.Icon(
              material.Icons.folder_open_rounded,
              size: 18,
              color: accent,
            ),
          ),
          const Gap(4),
          IconButton.ghost(
            onPressed: onSaveSqlFile,
            icon: material.Icon(
              material.Icons.save_outlined,
              size: 18,
              color: accent,
            ),
          ),
          const Gap(8),
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
    );
  }
}
