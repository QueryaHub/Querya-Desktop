import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_cross_fade_stack.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_workspace.dart';
import 'package:querya_desktop/features/postgresql/postgres_stats_view.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// When a PostgreSQL connection is selected but no tree object: Server stats or SQL editor.
class PostgresWorkspaceHome extends material.StatefulWidget {
  const PostgresWorkspaceHome({
    super.key,
    required this.connectionRow,
    this.postgresSqlEditorContext,
    this.postgresSqlEditorContextToken = 0,
    this.sqlTabRequestToken = 0,
    this.lastSelectedPostgresObject,
    this.onRestoreLastSelectedObject,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final bool isReadOnly;

  /// Remembers the last visited table/view for 1-click return.
  final ({
    String database,
    String schema,
    String name,
    PostgresObjectKind kind
  })? lastSelectedPostgresObject;
  final VoidCallback? onRestoreLastSelectedObject;

  /// Set when opening SQL from the tree (e.g. "Open in SQL") to seed session DB + template.
  final ({
    String database,
    String schema,
    String name,
    PostgresObjectKind kind
  })? postgresSqlEditorContext;

  /// Bumps when [postgresSqlEditorContext] should be applied to the editor.
  final int postgresSqlEditorContextToken;

  /// Parent increments this to request switching to the SQL tab (e.g. from browser context menu).
  final int sqlTabRequestToken;

  @override
  material.State<PostgresWorkspaceHome> createState() =>
      _PostgresWorkspaceHomeState();
}

class _PostgresWorkspaceHomeState
    extends material.State<PostgresWorkspaceHome> {
  int _tab = 0;
  late final material.ValueNotifier<bool?> _sqlTxNotifier;
  int _lastAppliedSqlTabToken = 0;

  @override
  void initState() {
    super.initState();
    _sqlTxNotifier = material.ValueNotifier<bool?>(null);
    _lastAppliedSqlTabToken = widget.sqlTabRequestToken;
  }

  @override
  void didUpdateWidget(covariant PostgresWorkspaceHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _lastAppliedSqlTabToken = widget.sqlTabRequestToken;
      return;
    }
    final t = widget.sqlTabRequestToken;
    if (t > _lastAppliedSqlTabToken) {
      _lastAppliedSqlTabToken = t;
      material.WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_selectTab(1));
      });
    }
  }

  @override
  void dispose() {
    _sqlTxNotifier.dispose();
    super.dispose();
  }

  Future<void> _selectTab(int i) async {
    if (i == _tab) return;
    if (_tab == 1 && i == 0 && _sqlTxNotifier.value == true) {
      final ok = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => material.AlertDialog(
          title: const material.Text('Open transaction'),
          content: const material.Text(
            'The SQL tab has an open transaction. Leave anyway? '
            'Uncommitted work may be lost if the session ends.',
          ),
          actions: [
            material.TextButton(
              onPressed: () => material.Navigator.of(ctx).pop(false),
              child: const material.Text('Stay'),
            ),
            material.TextButton(
              onPressed: () => material.Navigator.of(ctx).pop(true),
              child: const material.Text('Leave'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _tab = i);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Container(
          constraints: const material.BoxConstraints(minHeight: 44),
          padding: const material.EdgeInsets.symmetric(horizontal: 12),
          decoration: material.BoxDecoration(
            color: theme.colorScheme.muted.withValues(alpha: 0.6),
          ),
          child: material.Row(
            children: [
              const Text('PostgreSQL').semiBold().small(),
              if (widget.isReadOnly) ...[
                const Gap(6),
                material.Icon(
                  material.Icons.lock_outline_rounded,
                  size: 14,
                  color: theme.colorScheme.mutedForeground,
                ),
              ],
              if (widget.lastSelectedPostgresObject != null &&
                  widget.onRestoreLastSelectedObject != null) ...[
                const Gap(12),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: widget.onRestoreLastSelectedObject,
                  leading: const material.Icon(
                    material.Icons.table_chart_outlined,
                    size: 14,
                  ),
                  child: Text('Return to ${widget.lastSelectedPostgresObject!.name}'),
                ),
              ],
              const Spacer(),
              QueryaTabStrip(
                labels: const ['Server', 'SQL'],
                selectedIndex: _tab,
                onSelected: (index) => unawaited(_selectTab(index)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: QueryaCrossFadeStack(
            index: _tab,
            children: [
              PostgresStatsView(
                key: ValueKey('pg_stats_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
              ),
              PostgresSqlWorkspace(
                key: ValueKey('pg_sql_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
                transactionOpenNotifier: _sqlTxNotifier,
                postgresSqlEditorContext: widget.postgresSqlEditorContext,
                postgresSqlEditorContextToken:
                    widget.postgresSqlEditorContextToken,
                isReadOnly: widget.isReadOnly,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
