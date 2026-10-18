import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Gap, TextExtension;

/// Group entries of a card's menu: group it (with the marked tables), add it
/// to a group, take it out of its group.
List<MenuItem> erdGroupMenu({
  required String table,
  required Set<String> marked,
  required List<ErdGroup> groups,
  required ErdGroup? current,
  required material.Color mutedColor,
  required void Function(Set<String> tables) onNewGroup,
  required void Function(String id, Set<String> tables) onAddToGroup,
  required void Function(String table) onRemoveFromGroup,
}) {
  final tables = {...marked, table};
  return [
    MenuButton(
      key: material.ValueKey('erd_menu_group_$table'),
      onPressed: (_) => onNewGroup(tables),
      // The way to put more tables in is not obvious: say it here.
      trailing: tables.length == 1
          ? Text('Shift+click marks more',
              style: material.TextStyle(fontSize: 11, color: mutedColor))
          : null,
      child: Text(tables.length == 1
          ? 'New group…'
          : 'Group ${tables.length} tables…'),
    ),
    if (groups.any((g) => g.id != current?.id))
      MenuButton(
        subMenu: [
          for (final g in groups)
            if (g.id != current?.id)
              MenuButton(
                onPressed: (_) => onAddToGroup(g.id, tables),
                child: Text(g.name),
              ),
        ],
        child: const Text('Add to group'),
      ),
    if (current != null)
      MenuButton(
        key: material.ValueKey('erd_menu_ungroup_$table'),
        onPressed: (_) => onRemoveFromGroup(table),
        child: Text('Remove from ${current.name}'),
      ),
  ];
}
