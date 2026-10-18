import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/services/data_export_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Standard toolbar for [ExtensionTableView] with title, pagination chip, DDL inspection, custom filter toggle, export/save actions, and navigation.
class ExtensionTableToolbar extends material.StatelessWidget {
  const ExtensionTableToolbar({
    super.key,
    required this.title,
    required this.paginationLabel,
    required this.tableIcon,
    required this.loading,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.filterActive,
    required this.filterText,
    required this.onToggleFilter,
    required this.onOpenDdl,
    required this.onGoPrevious,
    required this.onGoNext,
    required this.onRefresh,
    this.onCancelQuery,
    this.onCopyFormat,
    this.onSaveFormat,
    this.onNavigateHome,
    this.onRestartDriver,
    this.isRestarting = false,
    this.editAction,
  });

  final String title;
  final String paginationLabel;
  final material.IconData tableIcon;
  final bool loading;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool filterActive;
  final String filterText;
  final VoidCallback onToggleFilter;
  final VoidCallback onOpenDdl;
  final VoidCallback onGoPrevious;
  final VoidCallback onGoNext;
  final VoidCallback onRefresh;
  final VoidCallback? onCancelQuery;
  final material.ValueChanged<DataExportFormat>? onCopyFormat;
  final material.ValueChanged<DataExportFormat>? onSaveFormat;
  final VoidCallback? onNavigateHome;
  final VoidCallback? onRestartDriver;
  final bool isRestarting;

  /// View / edit mode toggle ([TableEditModeButton]).
  final material.Widget? editAction;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = context.colors;
    final isFiltered = filterActive || filterText.trim().isNotEmpty;

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
              message: 'Return to driver overview',
              child: QueryaButton.secondary(
                label: 'Driver',
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
                          label: 'DDL',
                          icon: material.Icons.code_rounded,
                          onPressed: onOpenDdl,
                          size: QueryaControlSize.sm,
                        ),
                        const Gap(4),
                        QueryaButton.secondary(
                          label: isFiltered ? 'Filter (active)' : 'Filter',
                          icon: isFiltered
                                ? material.Icons.filter_alt_rounded
                                : material.Icons.filter_alt_outlined,
                          onPressed: onToggleFilter,
                          size: QueryaControlSize.sm,
                        ),
                        if (onCopyFormat != null) ...[
                          const Gap(4),
                          ExportMenuButton(
                            label: 'Copy',
                            icon: material.Icons.copy_rounded,
                            isSave: false,
                            onSelected: onCopyFormat!,
                          ),
                        ],
                        if (onSaveFormat != null) ...[
                          const Gap(4),
                          ExportMenuButton(
                            label: 'Export',
                            icon: material.Icons.file_download_outlined,
                            isSave: true,
                            onSelected: onSaveFormat!,
                          ),
                        ],
                        if (loading && onCancelQuery != null) ...[
                          const Gap(4),
                          QueryaButton.ghost(
                            label: 'Cancel',
                            icon: material.Icons.cancel_outlined,
                            onPressed: onCancelQuery,
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
                        if (onRestartDriver != null) ...[
                          QueryaButton.secondary(
                            label: isRestarting ? 'Restarting...' : 'Restart Driver',
                            icon: material.Icons.restart_alt_rounded,
                            loading: isRestarting,
                            onPressed: loading || isRestarting ? null : onRestartDriver,
                            size: QueryaControlSize.sm,
                          ),
                          const Gap(4),
                        ],
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
