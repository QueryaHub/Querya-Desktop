import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_cross_fade_stack.dart';
import 'package:querya_desktop/core/storage/local_db.dart' show ConnectionRow;
import 'package:querya_desktop/features/sqlite/sqlite_overview_tab.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

class SqliteWorkspaceHome extends material.StatefulWidget {
  const SqliteWorkspaceHome({
    super.key,
    required this.connectionRow,
    this.sqlTabRequestToken = 0,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final int sqlTabRequestToken;
  final bool isReadOnly;

  @override
  material.State<SqliteWorkspaceHome> createState() =>
      _SqliteWorkspaceHomeState();
}

class _SqliteWorkspaceHomeState extends material.State<SqliteWorkspaceHome> {
  int _tab = 0;
  int _lastAppliedSqlTabToken = 0;

  @override
  void initState() {
    super.initState();
    _lastAppliedSqlTabToken = widget.sqlTabRequestToken;
  }

  @override
  void didUpdateWidget(covariant SqliteWorkspaceHome oldWidget) {
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
        setState(() => _tab = 1);
      });
    }
  }

  void _selectTab(int i) {
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
              const Text('SQLite').semiBold().small(),
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
                labels: const ['Overview', 'SQL'],
                selectedIndex: _tab,
                onSelected: _selectTab,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: QueryaCrossFadeStack(
            index: _tab,
            children: [
              SqliteOverviewTab(
                key: ValueKey('sqlite_overview_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
              ),
              SqliteSqlWorkspace(
                key: ValueKey('sqlite_sql_${widget.connectionRow.id}'),
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
