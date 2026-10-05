import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/features/mongodb/mongo_aggregation_stage.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_json_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_table_view.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Workspace for visually and interactively building, running, and inspecting
/// MongoDB Aggregation Pipelines step-by-step.
class MongoAggregationWorkspace extends material.StatefulWidget {
  const MongoAggregationWorkspace({
    super.key,
    required this.connection,
    required this.database,
    required this.collection,
    this.onBack,
    this.initialStages,
  });

  final MongoConnection connection;
  final String database;
  final String collection;
  final material.VoidCallback? onBack;
  final List<MongoAggregationStage>? initialStages;

  @override
  material.State<MongoAggregationWorkspace> createState() =>
      _MongoAggregationWorkspaceState();
}

class _MongoAggregationWorkspaceState
    extends material.State<MongoAggregationWorkspace> {
  late List<MongoAggregationStage> _stages;
  List<Map<String, dynamic>> _results = [];
  bool _executing = false;
  String? _executionError;
  int? _lastExecutionDurationMs;
  int? _executedUpToStageIndex;
  bool _jsonViewMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialStages != null && widget.initialStages!.isNotEmpty) {
      _stages = List.from(widget.initialStages!);
    } else {
      _stages = [
        MongoAggregationStage(
          id: 'stage_1',
          operator: r'$match',
          queryText: templateForOperator(r'$match'),
          isEnabled: true,
        ),
      ];
    }
  }

  // ─── Stage management ──────────────────────────────────────────────────────

  void _addStage([String operator = r'$match']) {
    setState(() {
      final newIndex = _stages.length + 1;
      _stages.add(
        MongoAggregationStage(
          id: 'stage_${DateTime.now().microsecondsSinceEpoch}_$newIndex',
          operator: operator,
          queryText: templateForOperator(operator),
          isEnabled: true,
        ),
      );
    });
  }

  void _removeStage(int index) {
    if (_stages.length <= 1) {
      showAppToast(
        context: context,
        message: 'Pipeline must contain at least one stage',
        variant: AppToastVariant.info,
      );
      return;
    }
    setState(() {
      _stages.removeAt(index);
    });
  }

  void _moveStage(int from, int to) {
    if (to < 0 || to >= _stages.length) return;
    setState(() {
      final stage = _stages.removeAt(from);
      _stages.insert(to, stage);
    });
  }

  void _toggleStageEnabled(int index, bool enabled) {
    setState(() {
      _stages[index] = _stages[index].copyWith(isEnabled: enabled);
    });
  }

  void _updateStageOperator(int index, String newOp) {
    setState(() {
      final current = _stages[index];
      _stages[index] = current.copyWith(
        operator: newOp,
        queryText: templateForOperator(newOp),
        clearError: true,
        clearMetrics: true,
      );
    });
  }

  void _updateStageQuery(int index, String newQuery) {
    setState(() {
      _stages[index] = _stages[index].copyWith(
        queryText: newQuery,
        error: validateStage(_stages[index].copyWith(queryText: newQuery)),
      );
    });
  }

  // ─── Execution ─────────────────────────────────────────────────────────────

  Future<void> _runPipeline({int? upToStageIndex}) async {
    // Validate all participating stages first
    final targetLimit = upToStageIndex ?? (_stages.length - 1);
    for (int i = 0; i <= targetLimit; i++) {
      final stage = _stages[i];
      if (!stage.isEnabled) continue;
      final err = validateStage(stage);
      if (err != null) {
        setState(() {
          _stages[i] = stage.copyWith(error: err);
          _executionError =
              'Stage #${i + 1} (${stage.operator}) has a syntax error: $err';
        });
        return;
      }
    }

    setState(() {
      _executing = true;
      _executionError = null;
      _executedUpToStageIndex = upToStageIndex;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final pipeline = buildPipeline(_stages, upToStageIndex: upToStageIndex);
      final docs = await MongoService.instance.aggregate(
        widget.connection,
        widget.database,
        widget.collection,
        pipeline,
      );
      stopwatch.stop();

      if (!mounted) return;
      setState(() {
        _results = docs;
        _lastExecutionDurationMs = stopwatch.elapsedMilliseconds;
        _executing = false;

        // Record metrics on target stage if applicable
        if (upToStageIndex != null && upToStageIndex < _stages.length) {
          _stages[upToStageIndex] = _stages[upToStageIndex].copyWith(
            executionDurationMs: stopwatch.elapsedMilliseconds,
            outputCount: docs.length,
            clearError: true,
          );
        } else if (_stages.isNotEmpty) {
          _stages.last = _stages.last.copyWith(
            executionDurationMs: stopwatch.elapsedMilliseconds,
            outputCount: docs.length,
            clearError: true,
          );
        }
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _executing = false;
        _executionError = e.toString();
      });
    }
  }

  void _showExportDialog() {
    material.showDialog<void>(
      context: context,
      builder: (dialogCtx) => _ExportDialog(
        database: widget.database,
        collection: widget.collection,
        stages: _stages,
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return material.Container(
      color: cs.background,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          // Top action bar
          _buildActionBar(cs),
          const Divider(height: 1),
          // Main content: responsive layout
          material.Expanded(
            child: material.LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return material.Row(
                    crossAxisAlignment: material.CrossAxisAlignment.stretch,
                    children: [
                      // Left pane: Stages builder
                      material.SizedBox(
                        width: (constraints.maxWidth * 0.45).clamp(380.0, 560.0),
                        child: _buildStagesPane(cs),
                      ),
                      const VerticalDivider(width: 1),
                      // Right pane: Results
                      material.Expanded(
                        child: _buildResultsPane(cs),
                      ),
                    ],
                  );
                } else {
                  // Narrow viewport: vertical split
                  return material.Column(
                    children: [
                      material.Expanded(
                        flex: 5,
                        child: _buildStagesPane(cs),
                      ),
                      const Divider(height: 1),
                      material.Expanded(
                        flex: 5,
                        child: _buildResultsPane(cs),
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  material.Widget _buildActionBar(ColorScheme cs) {
    final enabledCount = _stages.where((s) => s.isEnabled).length;

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
                leading: const material.Icon(material.Icons.arrow_back_rounded,
                    size: 14),
                child: const Text('Back to Documents'),
              ),
              const Gap(12),
            ],
            material.Icon(
              material.Icons.auto_awesome_motion_rounded,
              size: 18,
              color: cs.primary,
            ),
            const Gap(8),
            Text('Aggregation Pipeline: ${widget.collection}')
                .semiBold()
                .medium(),
            const Gap(8),
            QueryaBadge.status(
              '$enabledCount / ${_stages.length} active',
              status: QueryaBadgeStatus.neutral,
            ),
            if (_lastExecutionDurationMs != null) ...[
              const Gap(8),
              QueryaBadge.status(
                '${_results.length} docs in ${_lastExecutionDurationMs}ms',
                status: QueryaBadgeStatus.success,
              ),
            ],
            const Gap(16),
            OutlineButton(
              onPressed: () => _addStage(),
              size: ButtonSize.small,
              leading:
                  const material.Icon(material.Icons.add_rounded, size: 14),
              child: const Text('Add Stage'),
            ),
            const Gap(8),
            OutlineButton(
              onPressed: _showExportDialog,
              size: ButtonSize.small,
              leading:
                  const material.Icon(material.Icons.code_rounded, size: 14),
              child: const Text('Export Code'),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: _executing ? null : () => _runPipeline(),
              size: ButtonSize.small,
              leading: _executing
                  ? const QueryaSpinner(size: QueryaSpinnerSize.sm)
                  : const material.Icon(material.Icons.play_arrow_rounded,
                      size: 16),
              child: Text(_executing ? 'Running...' : 'Run Pipeline'),
            ),
          ],
        ),
      ),
    );
  }

  material.Widget _buildStagesPane(ColorScheme cs) {
    return material.Container(
      color: cs.card.withValues(alpha: 0.35),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Padding(
            padding: const material.EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: material.Row(
              children: [
                const Text('Pipeline Stages').semiBold(),
                const material.Spacer(),
                Text('${_stages.length} stages').muted().small(),
              ],
            ),
          ),
          const Divider(height: 1),
          material.Expanded(
            child: material.ListView.separated(
              padding: const material.EdgeInsets.all(12),
              itemCount: _stages.length + 1,
              separatorBuilder: (_, __) => const Gap(12),
              itemBuilder: (context, index) {
                if (index == _stages.length) {
                  return material.Center(
                    child: OutlineButton(
                      onPressed: () => _addStage(),
                      size: ButtonSize.small,
                      leading: const material.Icon(
                        material.Icons.add_circle_outline_rounded,
                        size: 14,
                      ),
                      child: const Text('Add Next Stage'),
                    ),
                  );
                }

                final stage = _stages[index];
                return _StageCard(
                  key: ValueKey(stage.id),
                  stage: stage,
                  index: index,
                  isFirst: index == 0,
                  isLast: index == _stages.length - 1,
                  onToggleEnabled: (val) => _toggleStageEnabled(index, val),
                  onOperatorChanged: (op) => _updateStageOperator(index, op),
                  onQueryChanged: (query) => _updateStageQuery(index, query),
                  onMoveUp: () => _moveStage(index, index - 1),
                  onMoveDown: () => _moveStage(index, index + 1),
                  onDelete: () => _removeStage(index),
                  onRunUpToHere: () => _runPipeline(upToStageIndex: index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  material.Widget _buildResultsPane(ColorScheme cs) {
    final title = _executedUpToStageIndex == null
        ? 'Pipeline Results'
        : 'Results after Stage #${_executedUpToStageIndex! + 1} (${_stages[_executedUpToStageIndex!].operator})';

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        // Results header
        material.Container(
          padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: cs.card,
          child: material.Row(
            children: [
              Text(title).semiBold(),
              const material.Spacer(),
              if (_results.isNotEmpty) ...[
                Text('${_results.length} documents').muted().small(),
                const Gap(12),
              ],
              material.SizedBox(
                height: 28,
                child: material.SegmentedButton<bool>(
                  segments: const [
                    material.ButtonSegment(
                      value: false,
                      label: material.Text('Table'),
                      icon: material.Icon(
                        material.Icons.table_chart_rounded,
                        size: 14,
                      ),
                    ),
                    material.ButtonSegment(
                      value: true,
                      label: material.Text('JSON'),
                      icon: material.Icon(
                        material.Icons.code_rounded,
                        size: 14,
                      ),
                    ),
                  ],
                  selected: {_jsonViewMode},
                  onSelectionChanged: (selected) {
                    setState(() => _jsonViewMode = selected.first);
                  },
                  showSelectedIcon: false,
                  style: material.SegmentedButton.styleFrom(
                    padding: const material.EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: material.VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Error banner if any
        if (_executionError != null)
          material.Container(
            padding: const material.EdgeInsets.all(12),
            color: cs.destructive.withValues(alpha: 0.1),
            child: material.Row(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                material.Icon(
                  material.Icons.error_outline_rounded,
                  size: 16,
                  color: cs.destructive,
                ),
                const Gap(8),
                material.Expanded(
                  child: material.SelectableText(
                    _executionError!,
                    style: material.TextStyle(
                      color: cs.destructive,
                      fontSize: 13,
                    ),
                  ),
                ),
                material.InkWell(
                  onTap: () => setState(() => _executionError = null),
                  child: material.Icon(
                    material.Icons.close_rounded,
                    size: 16,
                    color: cs.destructive,
                  ),
                ),
              ],
            ),
          ),
        // Results content
        material.Expanded(
          child: _executing
              ? const material.Center(
                  child: QueryaSpinner(
                    size: QueryaSpinnerSize.lg,
                    label: 'Executing aggregation pipeline...',
                  ),
                )
              : _results.isEmpty
                  ? const QueryaEmptyState(
                      icon: material.Icon(
                        material.Icons.auto_awesome_motion_rounded,
                        size: 40,
                      ),
                      title: 'No Documents Yet',
                      description:
                          'Add stages, configure query filters/aggregations, and click "Run Pipeline" or "Run up to here" on any stage.',
                    )
                  : _jsonViewMode
                      ? MongoDocumentsJsonView(documents: _results)
                      : MongoDocumentsTableView(documents: _results),
        ),
      ],
    );
  }
}

// ─── Stage card widget ────────────────────────────────────────────────────────

class _StageCard extends material.StatefulWidget {
  const _StageCard({
    super.key,
    required this.stage,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onToggleEnabled,
    required this.onOperatorChanged,
    required this.onQueryChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onRunUpToHere,
  });

  final MongoAggregationStage stage;
  final int index;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<bool> onToggleEnabled;
  final ValueChanged<String> onOperatorChanged;
  final ValueChanged<String> onQueryChanged;
  final material.VoidCallback onMoveUp;
  final material.VoidCallback onMoveDown;
  final material.VoidCallback onDelete;
  final material.VoidCallback onRunUpToHere;

  @override
  material.State<_StageCard> createState() => _StageCardState();
}

class _StageCardState extends material.State<_StageCard> {
  late material.TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = material.TextEditingController(text: widget.stage.queryText);
  }

  @override
  void didUpdateWidget(covariant _StageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage.queryText != widget.stage.queryText &&
        _textController.text != widget.stage.queryText) {
      _textController.text = widget.stage.queryText;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stage = widget.stage;
    final syntaxError = validateStage(stage);

    return Card(
      child: material.Padding(
        padding: const material.EdgeInsets.all(12),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            // Stage header
            material.SingleChildScrollView(
              scrollDirection: material.Axis.horizontal,
              child: material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  QueryaBadge(
                    label: '#${widget.index + 1}',
                  ),
                  const Gap(8),
                  // Operator selector via QueryaDropdown
                  material.SizedBox(
                    width: 140,
                    child: QueryaDropdown<String>(
                      value: stage.operator,
                      items: [
                        for (final opInfo in kMongoStageOperators)
                          QueryaDropdownItem<String>(
                            value: opInfo.op,
                            label: opInfo.op,
                          ),
                      ],
                      onSelected: (val) {
                        if (val != null) widget.onOperatorChanged(val);
                      },
                    ),
                  ),
                  const Gap(8),
                  Switch(
                    value: stage.isEnabled,
                    onChanged: widget.onToggleEnabled,
                  ),
                  if (!stage.isEnabled)
                    const Text('Disabled').muted().small(),
                  const Gap(8),
                  if (stage.executionDurationMs != null) ...[
                    QueryaBadge.status(
                      '${stage.outputCount ?? 0} docs (${stage.executionDurationMs}ms)',
                      status: QueryaBadgeStatus.success,
                    ),
                    const Gap(6),
                  ],
                  QueryaIconButton(
                    icon: const material.Icon(material.Icons.arrow_upward_rounded),
                    tooltip: 'Move Up',
                    density: QueryaIconButtonDensity.dense,
                    onPressed: widget.isFirst ? null : widget.onMoveUp,
                  ),
                  QueryaIconButton(
                    icon: const material.Icon(material.Icons.arrow_downward_rounded),
                    tooltip: 'Move Down',
                    density: QueryaIconButtonDensity.dense,
                    onPressed: widget.isLast ? null : widget.onMoveDown,
                  ),
                  QueryaIconButton(
                    icon: const material.Icon(material.Icons.delete_outline_rounded),
                    tooltip: 'Delete Stage',
                    density: QueryaIconButtonDensity.dense,
                    isDestructive: true,
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
            ),
            const Gap(8),
            // Code input body
            material.DecoratedBox(
              decoration: material.BoxDecoration(
                border: material.Border.all(
                  color: syntaxError != null ? cs.destructive : cs.border,
                ),
                borderRadius: material.BorderRadius.circular(6),
                color: cs.background,
              ),
              child: material.TextField(
                controller: _textController,
                maxLines: null,
                minLines: 3,
                style: const material.TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.4,
                ),
                decoration: const material.InputDecoration(
                  isDense: true,
                  border: material.InputBorder.none,
                  contentPadding: material.EdgeInsets.all(10),
                ),
                onChanged: widget.onQueryChanged,
              ),
            ),
            if (syntaxError != null) ...[
              const Gap(4),
              Text(
                syntaxError,
                style: material.TextStyle(
                  color: cs.destructive,
                  fontSize: 11.5,
                ),
              ),
            ],
            const Gap(8),
            // Footer actions: run up to here
            material.Row(
              children: [
                GhostButton(
                  onPressed: stage.isEnabled ? widget.onRunUpToHere : null,
                  size: ButtonSize.small,
                  leading: const material.Icon(
                    material.Icons.play_circle_outline_rounded,
                    size: 14,
                  ),
                  child: const Text('Run up to here'),
                ),
                const Gap(8),
                material.Expanded(
                  child: material.Text(
                    _operatorSummary(stage.operator),
                    textAlign: material.TextAlign.end,
                    overflow: material.TextOverflow.ellipsis,
                    style: material.TextStyle(
                      fontSize: 11,
                      color: cs.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _operatorSummary(String op) {
    for (final info in kMongoStageOperators) {
      if (info.op == op) return info.summary;
    }
    return '';
  }
}

// ─── Export Code Dialog ───────────────────────────────────────────────────────

class _ExportDialog extends material.StatefulWidget {
  const _ExportDialog({
    required this.database,
    required this.collection,
    required this.stages,
  });

  final String database;
  final String collection;
  final List<MongoAggregationStage> stages;

  @override
  material.State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends material.State<_ExportDialog> {
  int _selectedTab = 0;

  String _generateCode() {
    switch (_selectedTab) {
      case 0:
        return MongoAggregationExporter.toMongosh(
          database: widget.database,
          collection: widget.collection,
          stages: widget.stages,
        );
      case 1:
        return MongoAggregationExporter.toNodeJs(
          database: widget.database,
          collection: widget.collection,
          stages: widget.stages,
        );
      case 2:
        return MongoAggregationExporter.toPython(
          database: widget.database,
          collection: widget.collection,
          stages: widget.stages,
        );
      default:
        return '';
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final code = _generateCode();

    return QueryaModalDialog(
      title: const Text('Export Aggregation Pipeline'),
      description: const Text('Copy ready-to-run driver code for your pipeline'),
      constraints: const material.BoxConstraints(maxWidth: 680),
      content: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.SizedBox(
            height: 32,
            child: material.SegmentedButton<int>(
              segments: const [
                material.ButtonSegment(
                  value: 0,
                  label: material.Text('mongosh (Shell)'),
                ),
                material.ButtonSegment(
                  value: 1,
                  label: material.Text('Node.js'),
                ),
                material.ButtonSegment(
                  value: 2,
                  label: material.Text('Python'),
                ),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (selected) {
                setState(() => _selectedTab = selected.first);
              },
              showSelectedIcon: false,
              style: material.SegmentedButton.styleFrom(
                visualDensity: material.VisualDensity.compact,
              ),
            ),
          ),
          const Gap(12),
          material.Container(
            height: 280,
            padding: const material.EdgeInsets.all(12),
            decoration: material.BoxDecoration(
              color: cs.card,
              border: material.Border.all(color: cs.border),
              borderRadius: material.BorderRadius.circular(6),
            ),
            child: material.SingleChildScrollView(
              child: material.SelectableText(
                code,
                style: const material.TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        OutlineButton(
          onPressed: () => material.Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        PrimaryButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) {
              showAppToast(
                context: context,
                message: 'Pipeline code copied to clipboard',
                variant: AppToastVariant.success,
              );
              material.Navigator.of(context).pop();
            }
          },
          leading: const material.Icon(material.Icons.copy_rounded, size: 16),
          child: const Text('Copy to Clipboard'),
        ),
      ],
    );
  }
}
