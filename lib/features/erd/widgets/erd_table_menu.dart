import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The entries of a table card's context menu.
abstract final class ErdTableMenu {
  static List<MenuItem> items({
    required String table,
    required void Function(String table)? onOpenData,
    required void Function(String table)? onOpenInSql,
    required void Function(String table)? onShowRelations,
    required bool collapsed,
    required material.VoidCallback onToggleCollapsed,
    required material.VoidCallback onHide,
    required List<MenuItem> groupItems,
    required material.Color Function(String slot) slotColor,
    required void Function(String? slot) onHeaderColor,
  }) {
    return [
      if (onOpenData case final open?)
        MenuButton(
          key: material.ValueKey('erd_menu_open_$table'),
          onPressed: (_) => open(table),
          child: const Text('Open data'),
        ),
      if (onOpenInSql case final inSql?)
        MenuButton(
          key: material.ValueKey('erd_menu_sql_$table'),
          onPressed: (_) => inSql(table),
          child: const Text('Open in SQL'),
        ),
      if (onShowRelations case final relations?)
        MenuButton(
          key: material.ValueKey('erd_menu_relations_$table'),
          onPressed: (_) => relations(table),
          child: const Text('Show relations'),
        ),
      MenuButton(
        onPressed: (_) {
          Clipboard.setData(ClipboardData(text: table));
        },
        child: const Text('Copy name'),
      ),
      MenuButton(
        onPressed: (_) => onToggleCollapsed(),
        child: Text(collapsed ? 'Expand' : 'Collapse'),
      ),
      MenuButton(
        onPressed: (_) => onHide(),
        child: const Text('Hide from diagram'),
      ),
      ...groupItems,
      MenuButton(
        key: material.ValueKey('erd_menu_colour_$table'),
        subMenu: [
          MenuButton(
            onPressed: (_) => onHeaderColor(null),
            child: const Text('Default'),
          ),
          for (var i = 0; i < erdHeaderSlots.length; i++)
            MenuButton(
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
