import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:file_selector/file_selector.dart';
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
  final _sqlController = material.TextEditingController();
  final ValueNotifier<double> _topFraction = ValueNotifier(0.6);

  bool _running = false;
  bool _restartingDriver = false;
  String? _error;
  List<String> _columns = [];
  List<List<String>> _rows = [];
  String? _statusLine;

  int _historyMaxEntries = kDefaultSqlHistoryMaxEntries;
  int _resultMaxRows = kDefaultSqlResultMaxRows;
  double _editorFontSize = kDefaultSqlEditorFontSize;

  static const _previewRowLimit = 200;

  bool get _isDriverError {
    final err = _error;
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
        _error = null;
      });
      await _execute();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Driver restart failed: $e';
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
    if (widget.initialSql != null && widget.initialSql!.isNotEmpty) {
      _sqlController.text = widget.initialSql!;
    }
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
    _sqlController.dispose();
    _topFraction.dispose();
    super.dispose();
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
    _sqlController.value = material.TextEditingValue(
      text: sql,
      selection: material.TextSelection.collapsed(offset: sql.length),
    );
    unawaited(_execute());
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



  Future<void> _execute() async {
    if (_running) return;
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
      _statusLine = null;
    });

    try {
      final result = await ExtensionDriverSession.instance.query(
        widget.connectionRow,
        userSql,
        limit: _resultMaxRows,
      );
      if (!mounted) return;

      setState(() {
        _columns = result.columns;
        _rows = result.rows;
        if (result.columns.isEmpty && result.rows.isEmpty) {
          _statusLine = result.message ?? 'Command completed.';
        } else {
          final elapsed =
              result.elapsedMs != null ? ' in ${result.elapsedMs}ms' : '';
          final capped = result.rows.length >= _resultMaxRows;
          _statusLine = capped
              ? 'Showing first $_resultMaxRows row(s)$elapsed (result capped).'
              : '${result.rows.length} row(s)$elapsed.';
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _running = false;
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
      final name =
          'query_${DateTime.now().toIso8601String().replaceAll(':', '-')}.sql';
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

    return material.CallbackShortcuts(
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
              _ExtensionSqlToolbar(
                connectionName: widget.connectionRow.name,
                onExecute: _running ? null : () => unawaited(_execute()),
                running: _running,
                isRestarting: _restartingDriver,
                onRestartDriver: _running ? null : () => unawaited(_restartDriver()),
                onOpenSqlFile: () => unawaited(_openSqlFile()),
                onSaveSqlFile: () => unawaited(_saveSqlFile()),
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
                  columns: _columns,
                  rows: _rows,
                  errorMessage: _error,
                  isLoading: _running,
                  statusLine: _statusLine,
                  errorAction: _isDriverError
                      ? ExtensionDriverRecoveryBanner(
                          onRestart: () => unawaited(_restartDriver()),
                          isRestarting: _restartingDriver,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
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
