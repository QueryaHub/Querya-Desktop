import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Toolbar for [PostgresTableView]: title, pagination chip, actions (scrollable when narrow).
class PostgresTableToolbar extends material.StatelessWidget {
  const PostgresTableToolbar({
    super.key,
    required this.title,
    required this.paginationLabel,
    required this.tableIcon,
    required this.customSqlActive,
    required this.isMaterializedView,
    required this.loading,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onOpenSql,
    required this.onOpenPrivileges,
    required this.onRefreshMaterializedView,
    required this.onExitCustomMode,
    required this.onGoPrevious,
    required this.onGoNext,
    required this.onRefresh,
  });

  final String title;
  final String paginationLabel;
  final material.IconData tableIcon;
  final bool customSqlActive;
  final bool isMaterializedView;
  final bool loading;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onOpenSql;
  final VoidCallback onOpenPrivileges;
  final VoidCallback onRefreshMaterializedView;
  final VoidCallback onExitCustomMode;
  final VoidCallback onGoPrevious;
  final VoidCallback onGoNext;
  final VoidCallback onRefresh;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return material.Container(
      padding: const material.EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: material.BoxDecoration(
        color: cs.card,
        border: material.Border(
          bottom: material.BorderSide(
            color: cs.border.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: material.Row(
        children: [
          material.Icon(tableIcon, size: 18, color: cs.primary),
          const Gap(8),
          material.Expanded(
            child: material.Text(
              title,
              style: material.TextStyle(
                fontSize: 13,
                fontWeight: material.FontWeight.w600,
                color: cs.foreground,
              ),
              overflow: material.TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          material.Expanded(
            flex: 2,
            child: material.LayoutBuilder(
              builder: (context, constraints) {
                return material.SingleChildScrollView(
                  scrollDirection: material.Axis.horizontal,
                  child: material.ConstrainedBox(
                    constraints: material.BoxConstraints(
                      minWidth: constraints.maxWidth,
                    ),
                    child: material.Row(
                      mainAxisAlignment: material.MainAxisAlignment.end,
                      mainAxisSize: material.MainAxisSize.min,
                      children: [
                        material.Container(
                          padding: const material.EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: material.BoxDecoration(
                            color: cs.muted.withValues(alpha: 0.4),
                            borderRadius: material.BorderRadius.circular(4),
                          ),
                          child: material.Text(
                            paginationLabel,
                            style: material.TextStyle(
                              fontSize: 11,
                              color: cs.mutedForeground,
                            ),
                          ),
                        ),
                        const Gap(6),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: onOpenSql,
                          leading: const material.Icon(
                            material.Icons.code_rounded,
                            size: 16,
                          ),
                          child: const Text('SQL'),
                        ),
                        const Gap(4),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: onOpenPrivileges,
                          leading: const material.Icon(
                            material.Icons.admin_panel_settings_rounded,
                            size: 15,
                          ),
                          child: const Text('Privileges'),
                        ),
                        if (isMaterializedView && !customSqlActive) ...[
                          const Gap(4),
                          OutlineButton(
                            size: ButtonSize.small,
                            onPressed: loading ? null : onRefreshMaterializedView,
                            leading: const material.Icon(
                              material.Icons.sync_rounded,
                              size: 15,
                            ),
                            child: const Text('Refresh MV'),
                          ),
                        ],
                        if (customSqlActive) ...[
                          const Gap(4),
                          OutlineButton(
                            size: ButtonSize.small,
                            onPressed: loading ? null : onExitCustomMode,
                            leading: const material.Icon(
                              material.Icons.table_chart_rounded,
                              size: 16,
                            ),
                            child: const Text('Table'),
                          ),
                        ],
                        const Gap(4),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: canGoPrevious ? onGoPrevious : null,
                          leading: const material.Icon(
                            material.Icons.chevron_left_rounded,
                            size: 16,
                          ),
                          child: const Text('Back'),
                        ),
                        const Gap(4),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: canGoNext ? onGoNext : null,
                          leading: const material.Icon(
                            material.Icons.chevron_right_rounded,
                            size: 16,
                          ),
                          child: const Text('Next'),
                        ),
                        const Gap(8),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: loading ? null : onRefresh,
                          leading: const material.Icon(
                            material.Icons.refresh_rounded,
                            size: 14,
                          ),
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
