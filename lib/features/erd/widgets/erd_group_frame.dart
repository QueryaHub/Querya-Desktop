import 'dart:math' show max;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// A group's frame on the canvas: a tinted box that takes no pointer, and its
/// title, which drags the whole group and has the group's menu.
abstract final class ErdGroupFrame {
  /// The widgets of [group]'s frame, positioned in canvas space; empty when
  /// none of its tables is in [layout].
  static List<material.Widget> build({
    required ErdGroup group,
    required ErdLayout layout,
    required material.Color Function(String slot) slotColor,
    required bool dragging,
    required material.VoidCallback onFocusCanvas,
    required material.VoidCallback onDragStart,
    required void Function(material.Offset delta) onDragMove,
    required material.VoidCallback onDragEnd,
    required material.VoidCallback onEdit,
    required void Function(String slot) onColor,
    required material.VoidCallback onUngroup,
  }) {
    final g = group;
    final frame = layout.frameOf(g.tables);
    if (frame == null) return const [];
    final color = slotColor(g.color);
    final title = material.MouseRegion(
      cursor: dragging
          ? material.SystemMouseCursors.grabbing
          : material.SystemMouseCursors.grab,
      child: material.GestureDetector(
        key: material.ValueKey('erd_group_${g.id}'),
        dragStartBehavior: DragStartBehavior.down,
        onTapDown: (_) => onFocusCanvas(),
        onPanStart: (_) {
          onFocusCanvas();
          onDragStart();
        },
        onPanUpdate: (d) => onDragMove(d.delta),
        onPanEnd: (_) => onDragEnd(),
        onPanCancel: onDragEnd,
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Icon(
                g.isSchema
                    ? material.Icons.schema_outlined
                    : material.Icons.folder_open_rounded,
                size: 13,
                color: color),
            const material.SizedBox(width: 5),
            material.Flexible(
              child: Text(g.name,
                  maxLines: 1,
                  overflow: material.TextOverflow.ellipsis,
                  style: material.TextStyle(
                      fontSize: 12,
                      fontWeight: material.FontWeight.w600,
                      color: color)),
            ),
            if (g.note case final note?) ...[
              const material.SizedBox(width: 5),
              material.Tooltip(
                message: note,
                child: material.Icon(material.Icons.notes_rounded,
                    key: material.ValueKey('erd_group_note_${g.id}'),
                    size: 12,
                    color: color),
              ),
            ],
          ],
        ),
      ),
    );
    return [
      material.Positioned.fromRect(
        rect: frame,
        child: material.IgnorePointer(
          child: material.DecoratedBox(
            decoration: material.BoxDecoration(
              color: color.withValues(alpha: 0.05),
              borderRadius: material.BorderRadius.circular(12),
              border: material.Border.all(color: color.withValues(alpha: 0.55)),
            ),
          ),
        ),
      ),
      material.Positioned(
        left: frame.left + 10,
        top: frame.top + 3,
        width: max(0.0, frame.width - 20),
        height: ErdLayout.frameTitleHeight - 6,
        child: material.Align(
          alignment: material.Alignment.centerLeft,
          child: g.isSchema
              ? title
              : ContextMenu(
                  items: [
                    MenuButton(
                      key: material.ValueKey('erd_group_edit_${g.id}'),
                      onPressed: (_) => onEdit(),
                      child: const Text('Rename / note…'),
                    ),
                    MenuButton(
                      subMenu: [
                        for (var i = 0; i < erdHeaderSlots.length; i++)
                          MenuButton(
                            leading: material.Icon(material.Icons.circle,
                                size: 12, color: slotColor(erdHeaderSlots[i])),
                            onPressed: (_) => onColor(erdHeaderSlots[i]),
                            child: Text('Colour ${i + 1}'),
                          ),
                      ],
                      child: const Text('Colour'),
                    ),
                    MenuButton(
                      key: material.ValueKey('erd_group_ungroup_${g.id}'),
                      onPressed: (_) => onUngroup(),
                      child: const Text('Ungroup'),
                    ),
                  ],
                  child: title,
                ),
        ),
      ),
    ];
  }
}
