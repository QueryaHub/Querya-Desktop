import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:file_selector/file_selector.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/database/sql_limit.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/layout/vertical_split_pane.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Ad-hoc SQL editor + results for SQLite.
class SqliteSqlWorkspace extends material.StatefulWidget {
  const SqliteSqlWorkspace({
    super.key,
    required this.connectionRow,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final bool isReadOnly;

  @override
  material.State<SqliteSqlWorkspace> createState() => _SqliteSqlWorkspaceState();
}

class _SqliteSqlWorkspaceState extends material.State<SqliteSqlWorkspace> {
  final _sqlController = material.TextEditingController();
  final ValueNotifier<double> _topFraction = ValueNotifier(0.65);

  SqliteLease? _lease;

  bool _running = false;
  String? _error;
  List<String> _columns = [];
  List<List<String>> _rows = [];
  int? _affectedRows;
  String? _statusLine;
  DataGridStagingBuffer? _stagingBuffer;
  String? _lastExecutedSql;
  bool _savingChanges = false;

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
      onExecute: () {
        if (!_running) unawaited(_execute());
      },
    );
  }

  @override
  void didUpdateWidget(covariant SqliteSqlWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isReadOnly != widget.isReadOnly) {
      _lease?.release();
      _lease = null;
    }
  }

  Future<void> _loadWorkspaceSettings() async {
    final rows = await AppSettings.instance.getSqlResultMaxRows();
    final hist = await AppSettings.instance.getSqlHistoryMaxEntries();
    final font = await AppSettings.instance.getSqlEditorFontSize();
    if (!mounted) return;
    setState(() {
      _resultMaxRows = rows;
      _historyMaxEntries = hist;
      _editorFontSize = font;
    });
  }

  Future<void> _ensureLease() async {
    if (_lease != null && _lease!.connection.isConnected) return;
    _lease?.release();
    _lease = null;
    final lease = await SqliteService.instance.acquire(
      widget.connectionRow,
      mode: widget.isReadOnly ? SqliteSessionMode.readOnly : SqliteSessionMode.readWrite,
    );
    if (!mounted) {
      lease.release();
      return;
    }
    _lease = lease;
  }

  @override
  void dispose() {
    SqlEditorCommandBridge.instance
        .unregister(connectionId: widget.connectionRow.id);
    SqlWorkspaceSettingsRevision.listenable
        .removeListener(_appSettingsListener);
    _topFraction.dispose();
    _lease?.release();
    _stagingBuffer?.dispose();
    _stagingBuffer = null;
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
            _error = 'Could not connect to SQLite.';
            _running = false;
          });
        }
        return;
      }

      // Bound SELECT/WITH/VALUES at the engine before materializing rows.
      // Client-side take() remains as defense for PRAGMA/EXPLAIN and author LIMIT.
      final cap = _resultMaxRows;
      final sql = injectSqlLimit(userSql, cap);
      final results = await conn.execute(sql);

      if (!mounted) return;

      final cols = <String>[];
      if (results.isNotEmpty) {
        cols.addAll(results.first.keys);
      }

      final truncated = results.length > cap;
      final limitCount = truncated ? cap : results.length;
      final injectedLimit = sql != userSql;

      final rawRows = results.take(limitCount).map((row) {
        return cols.map((col) => row[col]).toList();
      }).toList();

      // Adaptive convert offloads to background compute for large row sets (#522).
      final outRows = await convertResultRowsToStringsAdaptive(rawRows);

      setState(() {
        _columns = cols;
        _rows = outRows;
        _affectedRows = null;
        _lastExecutedSql = userSql;
        _stagingBuffer?.dispose();
        _stagingBuffer = cols.isNotEmpty
            ? DataGridStagingBuffer(columns: cols, rows: outRows)
            : null;
        if (cols.isEmpty && outRows.isEmpty) {
          _statusLine = 'Command completed.';
        } else if (truncated || (injectedLimit && results.length >= cap)) {
          _statusLine = 'Showing first $cap row(s) (result capped).';
        } else {
          _statusLine = '${results.length} row(s).';
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
          _error = 'Query timed out: ${e.message ?? e}';
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

  Future<void> _applyStagedChanges() async {
    if (_stagingBuffer == null || !_stagingBuffer!.isDirty || _savingChanges) return;
    final target = _lastExecutedSql != null ? SqlTableTargetExtractor.extract(_lastExecutedSql!) : null;
    final tableName = target?.tableName ?? 'table';

    setState(() => _savingChanges = true);
    try {
      final plan = _stagingBuffer!.generateMutationPlan(
        dialect: SqlDialect.sqlite,
        tableName: tableName,
        schema: target?.schema,
      );
      if (plan.isEmpty) {
        setState(() => _savingChanges = false);
        return;
      }

      final confirmed = await showDmlPreviewDialog(
        context: context,
        plan: plan,
      );
      if (confirmed != true) {
        setState(() => _savingChanges = false);
        return;
      }

      await _ensureLease();
      final conn = _lease?.connection;
      if (conn == null || !conn.isConnected) {
        throw StateError('Could not connect to SQLite.');
      }

      for (final stmt in plan.statements) {
        await conn.execute(stmt.sql);
      }

      if (!mounted) return;
      final newRows = _stagingBuffer!.effectiveRows;
      _stagingBuffer?.dispose();
      setState(() {
        _rows = newRows;
        _stagingBuffer = DataGridStagingBuffer(columns: _columns, rows: _rows);
        _savingChanges = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _savingChanges = false);
        await showAppDialog<void>(
          context: context,
          builder: (ctx) => material.AlertDialog(
            title: const material.Text('Save Changes Failed'),
            content: material.Text(e.toString()),
            actions: [
              material.TextButton(
                onPressed: () => material.Navigator.of(ctx).pop(),
                child: const material.Text('OK'),
              ),
            ],
          ),
        );
      }
    }
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
            top: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                _SqliteSqlToolbar(
                  onExecute: _running ? null : _execute,
                  running: _running,
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
                ),
                const Divider(height: 1),
                material.Expanded(
                  child: QueryEditorTab(
                    controller: _sqlController,
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
                material.Expanded(
                  child: ResultsTab(
                    columns: _columns,
                    rows: _rows,
                    errorMessage: _error,
                    isLoading: _running,
                    affectedRows: _affectedRows,
                    statusLine: _statusLine,
                    stagingBuffer: _stagingBuffer,
                    onApplyChanges: widget.isReadOnly ? null : _applyStagedChanges,
                    isSaving: _savingChanges,
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

class _SqliteSqlToolbar extends material.StatelessWidget {
  const _SqliteSqlToolbar({
    required this.onExecute,
    required this.running,
    required this.onOpenPreferences,
    this.onOpenHistory,
  });

  final Future<void> Function()? onExecute;
  final bool running;
  final VoidCallback onOpenPreferences;
  final VoidCallback? onOpenHistory;

  @override
  material.Widget build(material.BuildContext context) {
    final accent = context.workbench.accent;
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: SqlEditorChrome.sqlToolbarDecoration(context),
      child: material.Row(
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
          IconButton.ghost(
            onPressed: running ? null : onOpenPreferences,
            icon: material.Icon(
              material.Icons.settings_rounded,
              size: 20,
              color: accent,
            ),
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
