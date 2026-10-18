import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

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
    this.onNavigateHome,
    this.editAction,
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
  final VoidCallback? onNavigateHome;

  /// View / edit mode toggle ([TableEditModeButton]).
  final material.Widget? editAction;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = context.colors;
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
          if (onNavigateHome != null) ...[
            material.Tooltip(
              message: 'Return to server overview',
              child: QueryaButton.secondary(
                label: 'Server',
                icon: material.Icons.dns_outlined,
                onPressed: onNavigateHome,
                size: QueryaControlSize.sm,
              ),
            ),
            const Gap(10),
          ],
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
                        if (editAction != null) ...[
                          editAction!,
                          const Gap(4),
                        ],
                        QueryaButton.secondary(
                          label: 'SQL',
                          icon: material.Icons.code_rounded,
                          onPressed: onOpenSql,
                          size: QueryaControlSize.sm,
                        ),
                        const Gap(4),
                        QueryaButton.secondary(
                          label: 'Privileges',
                          icon: material.Icons.admin_panel_settings_rounded,
                          onPressed: onOpenPrivileges,
                          size: QueryaControlSize.sm,
                        ),
                        if (isMaterializedView && !customSqlActive) ...[
                          const Gap(4),
                          QueryaButton.secondary(
                            label: 'Refresh MV',
                            icon: material.Icons.sync_rounded,
                            onPressed: loading ? null : onRefreshMaterializedView,
                            size: QueryaControlSize.sm,
                          ),
                        ],
                        if (customSqlActive) ...[
                          const Gap(4),
                          QueryaButton.secondary(
                            label: 'Table',
                            icon: material.Icons.table_chart_rounded,
                            onPressed: loading ? null : onExitCustomMode,
                            size: QueryaControlSize.sm,
                          ),
                        ],
                        const Gap(4),
                        QueryaButton.secondary(
                          label: 'Prev',
                          icon: material.Icons.chevron_left_rounded,
                          onPressed: canGoPrevious ? onGoPrevious : null,
                          size: QueryaControlSize.sm,
                        ),
                        const Gap(4),
                        QueryaButton.secondary(
                          label: 'Next',
                          icon: material.Icons.chevron_right_rounded,
                          onPressed: canGoNext ? onGoNext : null,
                          size: QueryaControlSize.sm,
                        ),
                        const Gap(8),
                        QueryaButton.secondary(
                          label: 'Refresh',
                          icon: material.Icons.refresh_rounded,
                          onPressed: loading ? null : onRefresh,
                          size: QueryaControlSize.sm,
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
