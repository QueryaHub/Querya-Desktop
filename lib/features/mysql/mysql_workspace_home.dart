import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_cross_fade_stack.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/mysql/mysql_sql_workspace.dart';
import 'package:querya_desktop/features/mysql/mysql_stats_view.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// When a MySQL connection is selected but no tree object: server summary or SQL editor.
class MysqlWorkspaceHome extends material.StatefulWidget {
  const MysqlWorkspaceHome({
    super.key,
    required this.connectionRow,
    this.sqlTabRequestToken = 0,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final bool isReadOnly;

  /// Parent increments to switch to the SQL tab (e.g. context menu on connection).
  final int sqlTabRequestToken;

  @override
  material.State<MysqlWorkspaceHome> createState() =>
      _MysqlWorkspaceHomeState();
}

class _MysqlWorkspaceHomeState extends material.State<MysqlWorkspaceHome> {
  int _tab = 0;
  int _lastAppliedSqlTabToken = 0;

  @override
  void initState() {
    super.initState();
    _lastAppliedSqlTabToken = widget.sqlTabRequestToken;
  }

  @override
  void didUpdateWidget(covariant MysqlWorkspaceHome oldWidget) {
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

  Future<void> _selectTab(int i) async {
    if (i == _tab) return;
    setState(() => _tab = i);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        material.Container(
          constraints: const material.BoxConstraints(minHeight: 44),
          padding: const material.EdgeInsets.symmetric(horizontal: 12),
          decoration: material.BoxDecoration(
            color: theme.colorScheme.muted.withValues(alpha: 0.6),
          ),
          child: material.Row(
            children: [
              const Text('MySQL').semiBold().small(),
              if (widget.isReadOnly) ...[
                const Gap(6),
                material.Icon(
                  material.Icons.lock_outline_rounded,
                  size: 14,
                  color: theme.colorScheme.mutedForeground,
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
              MysqlStatsView(
                key: ValueKey('mysql_stats_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
              ),
              MysqlSqlWorkspace(
                key: ValueKey('mysql_sql_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
                isReadOnly: widget.isReadOnly,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
