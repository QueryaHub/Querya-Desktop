import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_json_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_table_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_query_executor.dart';
import 'package:querya_desktop/features/mongodb/mql_parser.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

enum _ResultViewMode {
  grid,
  json,
}

class _QueryTabSession {
  _QueryTabSession({
    required this.id,
    required this.title,
    String initialQuery = '',
  })  : controller = material.TextEditingController(text: initialQuery),
        focusNode = material.FocusNode();

  final String id;
  String title;
  final material.TextEditingController controller;
  final material.FocusNode focusNode;

  List<Map<String, dynamic>> results = [];
  Duration? elapsed;
  String? summary;
  String? error;
  bool isLoading = false;
  _ResultViewMode viewMode = _ResultViewMode.grid;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

/// Interactive multi-tab MQL (MongoDB Query Language) and Shell Console workspace.
class MongoQueryWorkspace extends material.StatefulWidget {
  const MongoQueryWorkspace({
    super.key,
    required this.connection,
    required this.database,
    this.initialCollection,
    this.onBack,
    this.executor,
    this.initialQueries,
  });

  final MongoConnection connection;
  final String database;
  final String? initialCollection;
  final material.VoidCallback? onBack;
  final MongoQueryExecutor? executor;
  final List<String>? initialQueries;

  @override
  material.State<MongoQueryWorkspace> createState() =>
      _MongoQueryWorkspaceState();
}

class _MongoQueryWorkspaceState extends material.State<MongoQueryWorkspace> {
  final List<_QueryTabSession> _tabs = [];
  int _activeTabIndex = 0;
  int _tabCounter = 1;
  late final MongoQueryExecutor _executor;

  _QueryTabSession get _activeTab => _tabs[_activeTabIndex];

  @override
  void initState() {
    super.initState();
    _executor = widget.executor ?? const DefaultMongoQueryExecutor();

    if (widget.initialQueries != null && widget.initialQueries!.isNotEmpty) {
      for (final q in widget.initialQueries!) {
        _tabs.add(_QueryTabSession(
          id: 'tab_${_tabCounter++}',
          title: 'Query ${_tabs.length + 1}',
          initialQuery: q,
        ));
      }
    } else {
      final defaultQuery = widget.initialCollection != null
          ? 'db.${widget.initialCollection}.find({})'
          : 'db.runCommand({ ping: 1 })';
      _tabs.add(_QueryTabSession(
        id: 'tab_${_tabCounter++}',
        title: 'Query 1',
        initialQuery: defaultQuery,
      ));
    }
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  void _addNewTab() {
    setState(() {
      final num = ++_tabCounter;
      final defaultQuery = widget.initialCollection != null
          ? 'db.${widget.initialCollection}.find({})'
          : 'db.runCommand({ ping: 1 })';
      _tabs.add(_QueryTabSession(
        id: 'tab_$num',
        title: 'Query ${_tabs.length + 1}',
        initialQuery: defaultQuery,
      ));
      _activeTabIndex = _tabs.length - 1;
    });
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) return;
    setState(() {
      final removed = _tabs.removeAt(index);
      removed.dispose();
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  Future<void> _executeActiveTab() async {
    final tab = _activeTab;
    if (tab.isLoading) return;

    final query = tab.controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        tab.error = 'Query cannot be empty';
        tab.results = [];
        tab.summary = null;
      });
      return;
    }

    setState(() {
      tab.isLoading = true;
      tab.error = null;
    });

    try {
      final parsedCommand = MqlParser.parse(
        query,
        defaultCollection: widget.initialCollection,
      );

      final result = await _executor.execute(
        connection: widget.connection,
        database: widget.database,
        command: parsedCommand,
        defaultCollection: widget.initialCollection,
      );

      if (!mounted) return;

      setState(() {
        tab.isLoading = false;
        tab.results = result.documents;
        tab.elapsed = result.elapsed;
        tab.summary = result.summary;
        tab.error = null;
      });

      // Persist to query history
      unawaited(_saveHistory(query));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        tab.isLoading = false;
        tab.error = e.toString();
        tab.results = [];
        tab.summary = null;
      });
    }
  }

  Future<void> _saveHistory(String query) async {
    final connId = widget.connection.id;
    try {
      await LocalDb.instance.recordSqlQueryHistory(
        connectionId: connId,
        databaseName: widget.database,
        sqlText: query,
      );
    } catch (_) {
      // Best-effort history logging
    }
  }

  Future<void> _showHistory() async {
    final connId = widget.connection.id;

    final history = await LocalDb.instance.listSqlQueryHistory(
      connectionId: connId,
      databaseName: widget.database,
      limit: 30,
    );

    if (!mounted) return;

    await showAppDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return QueryaModalDialog(
          title: const Text('MQL Query History'),
          description: Text('${widget.database} — recent queries'),
          constraints: const material.BoxConstraints(maxWidth: 600, maxHeight: 500),
          content: history.isEmpty
              ? const material.Padding(
                  padding: material.EdgeInsets.all(24),
                  child: material.Center(
                    child: Text('No query history recorded yet'),
                  ),
                )
              : material.ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = history[i];
                    return material.ListTile(
                      dense: true,
                      title: material.Text(
                        item.sqlText,
                        maxLines: 2,
                        overflow: material.TextOverflow.ellipsis,
                        style: const material.TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      subtitle: material.Text(
                        item.recordedAt,
                        style: material.TextStyle(
                          fontSize: 11,
                          color: cs.mutedForeground,
                        ),
                      ),
                      trailing: const material.Icon(
                        material.Icons.arrow_forward_ios_rounded,
                        size: 12,
                      ),
                      onTap: () {
                        setState(() {
                          _activeTab.controller.text = item.sqlText;
                        });
                        material.Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
          actions: [
            OutlineButton(
              onPressed: () => material.Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tab = _activeTab;

    return material.CallbackShortcuts(
      bindings: {
        const material.SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
        ): _executeActiveTab,
        const material.SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
        ): _executeActiveTab,
      },
      child: material.Container(
        color: cs.background,
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            // Top action bar
            _buildTopBar(cs),
            const Divider(height: 1),
            // Tab strip
            _buildTabStrip(cs),
            const Divider(height: 1),
            // Main content split
            material.Expanded(
              child: material.Column(
                children: [
                  // Code editor panel (top half)
                  material.Expanded(
                    flex: 4,
                    child: material.Container(
                      color: cs.card,
                      child: QueryaCodeEditor(
                        key: ValueKey('editor_${tab.id}'),
                        controller: tab.controller,
                        language: QueryaCodeLanguage.json,
                        variant: QueryaCodeEditorVariant.material,
                        focusNode: tab.focusNode,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  // Result bar & timing stats
                  _buildResultBar(cs, tab),
                  const Divider(height: 1),
                  // Results view (bottom half)
                  material.Expanded(
                    flex: 6,
                    child: _buildResultsView(cs, tab),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  material.Widget _buildTopBar(ColorScheme cs) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.card,
      child: material.SingleChildScrollView(
        scrollDirection: material.Axis.horizontal,
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            if (widget.onBack != null) ...[
              OutlineButton(
                onPressed: widget.onBack,
                size: ButtonSize.small,
                leading: const material.Icon(
                  material.Icons.arrow_back_rounded,
                  size: 14,
                ),
                child: const Text('Back to Documents'),
              ),
              const Gap(12),
            ],
            material.Icon(
              material.Icons.terminal_rounded,
              size: 18,
              color: cs.primary,
            ),
            const Gap(8),
            Text('MQL Console — ${widget.database}')
                .semiBold()
                .medium(),
            const Gap(16),
            // History button
            QueryaIconButton(
              icon: const material.Icon(material.Icons.history_rounded),
              tooltip: 'Query History',
              density: QueryaIconButtonDensity.dense,
              onPressed: _showHistory,
            ),
            const Gap(8),
            // Run Query button
            PrimaryButton(
              onPressed: _activeTab.isLoading ? null : _executeActiveTab,
              size: ButtonSize.small,
              leading: _activeTab.isLoading
                  ? const QueryaSpinner(size: QueryaSpinnerSize.sm)
                  : const material.Icon(material.Icons.play_arrow_rounded, size: 16),
              child: const Text('Run Query (Ctrl+Enter)'),
            ),
          ],
        ),
      ),
    );
  }

  material.Widget _buildTabStrip(ColorScheme cs) {
    return material.Container(
      height: 38,
      padding: const material.EdgeInsets.symmetric(horizontal: 8),
      color: cs.card,
      child: QueryaTabStrip(
        labels: _tabs.map((t) => t.title).toList(),
        selectedIndex: _activeTabIndex,
        onSelected: (i) => setState(() => _activeTabIndex = i),
        onClose: _closeTab,
        onAdd: _addNewTab,
        canClose: _tabs.length > 1 ? (_) => true : (_) => false,
      ),
    );
  }

  material.Widget _buildResultBar(ColorScheme cs, _QueryTabSession tab) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: cs.card,
      child: material.SingleChildScrollView(
        scrollDirection: material.Axis.horizontal,
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Icon(
              material.Icons.table_chart_outlined,
              size: 16,
              color: cs.mutedForeground,
            ),
            const Gap(8),
            if (tab.summary != null) ...[
              Text(tab.summary!).semiBold().small(),
              const Gap(8),
            ],
            if (tab.elapsed != null) ...[
              QueryaBadge.status(
                '${tab.elapsed!.inMilliseconds} ms',
                status: QueryaBadgeStatus.info,
              ),
              const Gap(8),
            ],
            if (tab.results.isNotEmpty) ...[
              QueryaBadge.status(
                '${tab.results.length} rows',
                status: QueryaBadgeStatus.neutral,
              ),
              const Gap(8),
            ],
            const Gap(16),
            // Mode switchers: Grid vs JSON
            material.SizedBox(
              height: 32,
              width: 160,
              child: QueryaTabStrip(
                labels: const ['Grid', 'JSON'],
                selectedIndex: _ResultViewMode.values.indexOf(tab.viewMode),
                onSelected: (i) =>
                    setState(() => tab.viewMode = _ResultViewMode.values[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  material.Widget _buildResultsView(ColorScheme cs, _QueryTabSession tab) {
    if (tab.isLoading) {
      return const material.Center(
        child: QueryaSpinner(
          size: QueryaSpinnerSize.lg,
          label: 'Executing MQL query...',
        ),
      );
    }

    if (tab.error != null) {
      return material.Container(
        margin: const material.EdgeInsets.all(16),
        padding: const material.EdgeInsets.all(16),
        decoration: material.BoxDecoration(
          color: cs.destructive.withValues(alpha: 0.08),
          borderRadius: material.BorderRadius.circular(8),
          border: material.Border.all(color: cs.destructive.withValues(alpha: 0.3)),
        ),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Row(
              children: [
                material.Icon(
                  material.Icons.error_outline_rounded,
                  color: cs.destructive,
                  size: 18,
                ),
                const Gap(8),
                const Text('Query Error').semiBold(),
              ],
            ),
            const Gap(8),
            material.SelectableText(
              tab.error!,
              style: material.TextStyle(
                color: cs.destructive,
                fontFamily: 'monospace',
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      );
    }

    if (tab.results.isEmpty) {
      return QueryaEmptyState(
        icon: const material.Icon(
          material.Icons.terminal_rounded,
          size: 40,
        ),
        title: 'No Documents to Display',
        description: tab.summary ??
            'Run an MQL query (e.g. db.collection.find({})) or execute a command to view results.',
      );
    }

    if (tab.viewMode == _ResultViewMode.json) {
      return MongoDocumentsJsonView(documents: tab.results);
    }

    return MongoDocumentsTableView(documents: tab.results);
  }
}
