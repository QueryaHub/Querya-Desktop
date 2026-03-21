import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_workspace.dart';
import 'package:querya_desktop/features/postgresql/postgres_stats_view.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// When a PostgreSQL connection is selected but no tree object: Server stats or SQL editor.
class PostgresWorkspaceHome extends material.StatefulWidget {
  const PostgresWorkspaceHome({
    super.key,
    required this.connectionRow,
    this.sqlTabRequestToken = 0,
  });

  final ConnectionRow connectionRow;

  /// Parent increments this to request switching to the SQL tab (e.g. from browser context menu).
  final int sqlTabRequestToken;

  @override
  material.State<PostgresWorkspaceHome> createState() =>
      _PostgresWorkspaceHomeState();
}

class _PostgresWorkspaceHomeState extends material.State<PostgresWorkspaceHome> {
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
      final ok = await material.showDialog<bool>(
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
          height: 44,
          padding: const material.EdgeInsets.symmetric(horizontal: 12),
          decoration: material.BoxDecoration(
            color: theme.colorScheme.muted.withValues(alpha: 0.6),
          ),
          child: material.Row(
            children: [
              const Text('PostgreSQL').semiBold().small(),
              const Spacer(),
              ...List.generate(2, (i) {
                final labels = ['Server', 'SQL'];
                final selected = _tab == i;
                return material.Padding(
                  padding: const material.EdgeInsets.only(left: 6),
                  child: material.MouseRegion(
                    cursor: material.SystemMouseCursors.click,
                    child: material.GestureDetector(
                      onTap: () => _selectTab(i),
                      child: material.AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const material.EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: material.BoxDecoration(
                          color: selected
                              ? theme.colorScheme.background
                              : material.Colors.transparent,
                          borderRadius: material.BorderRadius.circular(6),
                        ),
                        child: selected
                            ? Text(labels[i]).small().semiBold()
                            : Text(labels[i])
                                .small()
                                .muted(),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: material.IndexedStack(
            index: _tab,
            sizing: material.StackFit.expand,
            children: [
              PostgresStatsView(
                key: ValueKey('pg_stats_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
              ),
              PostgresSqlWorkspace(
                key: ValueKey('pg_sql_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
                transactionOpenNotifier: _sqlTxNotifier,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
