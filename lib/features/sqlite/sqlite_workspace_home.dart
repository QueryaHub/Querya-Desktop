import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/storage/local_db.dart' show ConnectionRow;
import 'package:querya_desktop/features/sqlite/sqlite_sql_workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

class SqliteWorkspaceHome extends material.StatefulWidget {
  const SqliteWorkspaceHome({
    super.key,
    required this.connectionRow,
    this.sqlTabRequestToken = 0,
  });

  final ConnectionRow connectionRow;
  final int sqlTabRequestToken;

  @override
  material.State<SqliteWorkspaceHome> createState() => _SqliteWorkspaceHomeState();
}

class _SqliteWorkspaceHomeState extends material.State<SqliteWorkspaceHome> {
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
              const Spacer(),
              material.Container(
                padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: material.BoxDecoration(
                  color: theme.colorScheme.background,
                  borderRadius: material.BorderRadius.circular(6),
                ),
                child: const Text('SQL').small().semiBold(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SqliteSqlWorkspace(
            key: ValueKey('sqlite_sql_${widget.connectionRow.id}'),
            connectionRow: widget.connectionRow,
          ),
        ),
      ],
    );
  }
}
