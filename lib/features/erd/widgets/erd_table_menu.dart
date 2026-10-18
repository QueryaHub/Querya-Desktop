import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/shared/widgets/querya_context_menu.dart';

/// The entries of a table card's context menu.
abstract final class ErdTableMenu {
  static List<QueryaMenuItem> items({
    required String table,
    required void Function(String table)? onOpenData,
    required void Function(String table)? onOpenInSql,
    required void Function(String table)? onShowRelations,
    required bool collapsed,
    required material.VoidCallback onToggleCollapsed,
    required material.VoidCallback onHide,
    required List<QueryaMenuItem> groupItems,
    required material.Color Function(String slot) slotColor,
    required void Function(String? slot) onHeaderColor,
  }) {
    return [
      if (onOpenData case final open?)
        QueryaMenuItem(
          key: material.ValueKey('erd_menu_open_$table'),
          onPressed: (_) => open(table),
          child: const Text('Open data'),
        ),
      if (onOpenInSql case final inSql?)
        QueryaMenuItem(
          key: material.ValueKey('erd_menu_sql_$table'),
          onPressed: (_) => inSql(table),
          child: const Text('Open in SQL'),
        ),
      if (onShowRelations case final relations?)
        QueryaMenuItem(
          key: material.ValueKey('erd_menu_relations_$table'),
          onPressed: (_) => relations(table),
          child: const Text('Show relations'),
        ),
      QueryaMenuItem(
        onPressed: (_) {
          Clipboard.setData(ClipboardData(text: table));
        },
        child: const Text('Copy name'),
      ),
      QueryaMenuItem(
        onPressed: (_) => onToggleCollapsed(),
        child: Text(collapsed ? 'Expand' : 'Collapse'),
      ),
      QueryaMenuItem(
        onPressed: (_) => onHide(),
        child: const Text('Hide from diagram'),
      ),
      ...groupItems,
      QueryaMenuItem(
        key: material.ValueKey('erd_menu_colour_$table'),
        subMenu: [
          QueryaMenuItem(
            onPressed: (_) => onHeaderColor(null),
            child: const Text('Default'),
          ),
          for (var i = 0; i < erdHeaderSlots.length; i++)
            QueryaMenuItem(
              leading: material.Icon(
                material.Icons.circle,
                size: 12,
                color: slotColor(erdHeaderSlots[i]),
              ),
              onPressed: (_) => onHeaderColor(erdHeaderSlots[i]),
              child: Text('Colour ${i + 1}'),
            ),
        ],
        child: const Text('Header colour'),
      ),
    ];
  }
}
