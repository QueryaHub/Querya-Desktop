import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/services/data_export_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

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

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                          onPressed: onOpenDdl,
                          leading: const material.Icon(
                            material.Icons.code_rounded,
                            size: 16,
                          ),
                          child: const Text('DDL'),
                        ),
                        const Gap(4),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: onToggleFilter,
                          leading: material.Icon(
                            isFiltered
                                ? material.Icons.filter_alt_rounded
                                : material.Icons.filter_alt_outlined,
                            size: 15,
                          ),
                          child: Text(isFiltered ? 'Filter (active)' : 'Filter'),
                        ),
                        if (onCopyFormat != null) ...[
                          const Gap(4),
                          ExportMenuButton(
                            label: 'Copy ▾',
                            icon: material.Icons.copy_rounded,
                            isSave: false,
                            onSelected: onCopyFormat!,
                          ),
                        ],
                        if (onSaveFormat != null) ...[
                          const Gap(4),
                          ExportMenuButton(
                            label: 'Save ▾',
                            icon: material.Icons.save_alt_rounded,
                            isSave: true,
                            onSelected: onSaveFormat!,
                          ),
                        ],
                        if (loading && onCancelQuery != null) ...[
                          const Gap(4),
                          OutlineButton(
                            size: ButtonSize.small,
                            onPressed: onCancelQuery,
                            leading: const material.Icon(
                              material.Icons.cancel_outlined,
                              size: 15,
                            ),
                            child: const Text('Cancel'),
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
