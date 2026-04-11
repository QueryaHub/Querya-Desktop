import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
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
  });

  final ConnectionRow connectionRow;

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
          height: 44,
          padding: const material.EdgeInsets.symmetric(horizontal: 12),
          decoration: material.BoxDecoration(
            color: theme.colorScheme.muted.withValues(alpha: 0.6),
          ),
          child: material.Row(
            children: [
              const Text('MySQL').semiBold().small(),
              const Spacer(),
              ...List.generate(2, (i) {
                final labels = ['Server', 'SQL'];
                final selected = _tab == i;
                return material.Padding(
                  padding: const material.EdgeInsets.only(left: 6),
                  child: material.MouseRegion(
                    cursor: material.SystemMouseCursors.click,
                    child: material.GestureDetector(
                      onTap: () => unawaited(_selectTab(i)),
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
                            : Text(labels[i]).small().muted(),
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
              MysqlStatsView(
                key: ValueKey('mysql_stats_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
              ),
              MysqlSqlWorkspace(
                key: ValueKey('mysql_sql_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
