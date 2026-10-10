import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/querya_action_menu.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The toolbar's view switcher: All tables, the saved views, and the
/// commands to save, rename and delete one.
class ErdViewsMenu extends material.StatelessWidget {
  const ErdViewsMenu({
    super.key,
    required this.views,
    required this.active,
    required this.onShowAll,
    required this.onSwitch,
    required this.onNew,
    required this.onRename,
    required this.onDelete,
  });

  final List<ErdSavedView> views;

  /// The view the diagram is in, or null for *All tables*.
  final ErdSavedView? active;
  final material.VoidCallback onShowAll;
  final void Function(String id) onSwitch;
  final material.VoidCallback onNew;
  final material.VoidCallback onRename;
  final material.VoidCallback onDelete;

  /// [name] cut to 28 characters with an ellipsis, for menus and the toolbar.
  static String shortName(String name) =>
      name.length <= 28 ? name : '${name.substring(0, 27)}…';

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    final current = active;
    return QueryaActionMenu<String>(
      items: [
        // A mark on every row, so the labels line up.
        QueryaActionMenuItem(
          value: 'all',
          label: 'All tables',
          icon: current == null
              ? material.Icons.radio_button_checked_rounded
              : material.Icons.radio_button_unchecked_rounded,
        ),
        for (final v in views)
          QueryaActionMenuItem(
            value: 'view:${v.id}',
            label: '${shortName(v.name)} (${v.tables.length})',
            icon: v.id == current?.id
                ? material.Icons.radio_button_checked_rounded
                : material.Icons.radio_button_unchecked_rounded,
          ),
        const QueryaActionMenuItem(
          value: 'new',
          label: 'Save as new view…',
          icon: material.Icons.bookmark_add_outlined,
        ),
        if (current != null) ...[
          const QueryaActionMenuItem(
            value: 'rename',
            label: 'Rename view…',
            icon: material.Icons.edit_outlined,
          ),
          const QueryaActionMenuItem(
            value: 'delete',
            label: 'Delete view',
            icon: material.Icons.delete_outline_rounded,
          ),
        ],
      ],
      onSelected: (v) {
        switch (v) {
          case 'all':
            onShowAll();
          case 'new':
            onNew();
          case 'rename':
            onRename();
          case 'delete':
            onDelete();
          default:
            if (v.startsWith('view:')) onSwitch(v.substring(5));
        }
      },
      child: material.Padding(
        key: const material.ValueKey('erd_views'),
        padding:
            const material.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Icon(material.Icons.bookmarks_outlined,
                size: 16, color: wb.mutedForeground),
            const material.SizedBox(width: 6),
            Text(current == null ? 'All tables' : shortName(current.name)),
            const material.SizedBox(width: 4),
            material.Icon(material.Icons.expand_more_rounded,
                size: 16, color: wb.mutedForeground),
          ],
        ),
      ),
    );
  }
}
