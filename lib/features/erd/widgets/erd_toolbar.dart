import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/features/erd/widgets/erd_export_menu.dart';
import 'package:querya_desktop/features/workspace/sql_editor_chrome.dart';
import 'package:querya_desktop/shared/widgets/querya_button.dart';
import 'package:querya_desktop/shared/widgets/querya_tab_strip.dart';

/// The row above the diagram: refresh, detail level, views, notes, groups,
/// hidden tables, auto layout and export.
///
/// [ready] is whether there is a diagram to act on; the buttons that need one
/// are off without it. [viewsMenu] is null where views do not apply.
class ErdToolbar extends material.StatelessWidget {
  const ErdToolbar({
    super.key,
    required this.ready,
    required this.loading,
    required this.detail,
    required this.markedCount,
    required this.hiddenCount,
    required this.viewsMenu,
    required this.onRefresh,
    required this.onDetail,
    required this.onAddNote,
    required this.onGroupMarked,
    required this.onShowHidden,
    required this.onAutoLayout,
    required this.onExport,
  });

  final bool ready;
  final bool loading;
  final ErdDetail detail;
  final int markedCount;
  final int hiddenCount;
  final material.Widget? viewsMenu;
  final material.VoidCallback onRefresh;
  final void Function(ErdDetail detail) onDetail;
  final material.VoidCallback onAddNote;
  final material.VoidCallback onGroupMarked;
  final material.VoidCallback onShowHidden;
  final material.VoidCallback onAutoLayout;
  final void Function(ErdExportAction action) onExport;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      decoration: SqlEditorChrome.sqlToolbarDecoration(context),
      padding: const material.EdgeInsets.all(8),
      child: material.LayoutBuilder(
        builder: (context, constraints) {
          // Below ~1100 px the labels of Note, Auto layout and the hidden
          // tables button give way to icons (the tooltips keep the names) so
          // the toolbar stays on one row.
          final compact = constraints.maxWidth < 1100;
          return QueryaControlScope(
            size: QueryaControlSize.md,
            child: material.Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: material.WrapCrossAlignment.center,
              children: [
                QueryaButton.secondary(
                  key: const material.ValueKey('erd_refresh'),
                  label: 'Refresh',
                  icon: material.Icons.refresh_rounded,
                  onPressed: loading ? null : onRefresh,
                ),
                // Detail level for every card; a card collapsed by hand stays
                // collapsed (#1278).
                _dimmed(
                  material.Tooltip(
                    message: 'Table names only, key columns, or every column',
                    child: QueryaTabStrip(
                      key: const material.ValueKey('erd_detail'),
                      labels: const ['Names', 'Keys', 'All'],
                      selectedIndex: ErdDetail.values.indexOf(detail),
                      onSelected: (i) => onDetail(ErdDetail.values[i]),
                    ),
                  ),
                ),
                // Also with every table hidden: a view may be that empty, and
                // the way out is another view.
                if (viewsMenu case final menu?) menu,
                QueryaButton.secondary(
                  key: const material.ValueKey('erd_add_note'),
                  compact: compact,
                  label: 'Note',
                  icon: material.Icons.sticky_note_2_outlined,
                  tooltip: 'Add a sticky note to the diagram',
                  onPressed: ready ? onAddNote : null,
                ),
                if (markedCount > 0)
                  QueryaButton.secondary(
                    key: const material.ValueKey('erd_group_marked'),
                    compact: compact,
                    label: 'Group $markedCount '
                        '${markedCount == 1 ? 'table' : 'tables'}',
                    icon: material.Icons.folder_open_rounded,
                    tooltip: 'Shift / Ctrl + click marks more tables',
                    onPressed: onGroupMarked,
                  ),
                if (hiddenCount > 0)
                  QueryaButton.secondary(
                    key: const material.ValueKey('erd_show_all'),
                    compact: compact,
                    label: 'Show $hiddenCount hidden',
                    icon: material.Icons.visibility_outlined,
                    onPressed: onShowHidden,
                  ),
                QueryaButton.secondary(
                  key: const material.ValueKey('erd_auto_layout'),
                  compact: compact,
                  label: 'Auto layout',
                  icon: material.Icons.auto_fix_high_rounded,
                  tooltip: 'Arrange the tables again (undoes manual moves)',
                  onPressed: ready ? onAutoLayout : null,
                ),
                _dimmed(ErdExportMenu(onSelected: onExport)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// [child] half transparent and inert while there is no diagram.
  material.Widget _dimmed(material.Widget child) => material.IgnorePointer(
        ignoring: !ready,
        child: material.Opacity(opacity: ready ? 1 : 0.5, child: child),
      );
}
