import 'dart:async';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/layout/vertical_split_pane.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/features/main_screen/query_editor_tab.dart';
import 'package:querya_desktop/features/main_screen/results_tab.dart';
import 'package:querya_desktop/features/main_screen/sql_editor_chrome.dart';
import 'package:querya_desktop/features/main_screen/sql_query_history_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Ad-hoc SQL editor + results for SQLite.
class SqliteSqlWorkspace extends material.StatefulWidget {
  const SqliteSqlWorkspace({
    super.key,
    required this.connectionRow,
  });

  final ConnectionRow connectionRow;

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
    });
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
      mode: SqliteSessionMode.readWrite,
    );
    if (!mounted) {
      lease.release();
      return;
    }
    _lease = lease;
  }

  @override
  void dispose() {
    SqlWorkspaceSettingsRevision.listenable
        .removeListener(_appSettingsListener);
    _topFraction.dispose();
    _lease?.release();
    _sqlController.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    final userSql = _sqlController.text.trim();
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
            _error = 'Could not connect to SQLite.';
            _running = false;
          });
        }
        return;
      }

      final results = await conn.execute(userSql);

      if (!mounted) return;

      final cols = <String>[];
      if (results.isNotEmpty) {
        cols.addAll(results.first.keys);
      }

      final cap = _resultMaxRows;
      final truncated = results.length > cap;
      final limitCount = truncated ? cap : results.length;

      final rawRows = results.take(limitCount).toList();
      final outRows = rawRows.map((row) {
        return cols.map((col) {
          final val = row[col];
          return val == null ? 'NULL' : val.toString();
        }).toList();
      }).toList();

      setState(() {
        _columns = cols;
        _rows = outRows;
        _affectedRows = null;
        if (cols.isEmpty && outRows.isEmpty) {
          _statusLine = 'Command completed.';
        } else {
          _statusLine = truncated
              ? 'Showing first $cap row(s) (result capped).'
              : '${results.length} row(s).';
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

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);

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
              material.Expanded(
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
