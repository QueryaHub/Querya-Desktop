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
  });

  final ConnectionRow connectionRow;

  @override
  material.State<PostgresWorkspaceHome> createState() =>
      _PostgresWorkspaceHomeState();
}

class _PostgresWorkspaceHomeState extends material.State<PostgresWorkspaceHome> {
  int _tab = 0;

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
              Text('PostgreSQL').semiBold().small(),
              const Spacer(),
              ...List.generate(2, (i) {
                final labels = ['Server', 'SQL'];
                final selected = _tab == i;
                return material.Padding(
                  padding: const material.EdgeInsets.only(left: 6),
                  child: material.MouseRegion(
                    cursor: material.SystemMouseCursors.click,
                    child: material.GestureDetector(
                      onTap: () => setState(() => _tab = i),
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
          child: _tab == 0
              ? PostgresStatsView(
                  key: ValueKey('pg_stats_${widget.connectionRow.id}'),
                  connectionRow: widget.connectionRow,
                )
              : PostgresSqlWorkspace(
                  key: ValueKey('pg_sql_${widget.connectionRow.id}'),
                  connectionRow: widget.connectionRow,
                ),
        ),
      ],
    );
  }
}
