import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_note_text.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// A sticky note on the canvas: draggable by its body, resizable by its
/// corner, with an edit / colour / attach / delete menu (#1283).
///
/// Positioned in canvas space, so it goes straight into the canvas Stack. All
/// changes go out through callbacks; the note itself is immutable.
class ErdNoteCard extends material.StatelessWidget {
  const ErdNoteCard({
    super.key,
    required this.note,
    required this.tint,
    required this.slotColor,
    required this.dragging,
    required this.onFocusCanvas,
    required this.onDragStart,
    required this.onDragMove,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onEdit,
    required this.onChange,
    required this.onAttachNearest,
    required this.onDelete,
    required this.onResize,
    required this.onResizeEnd,
  });

  final ErdNote note;

  /// Tint of a note without a colour over the canvas.
  final double tint;
  final material.Color Function(String slot) slotColor;
  final bool dragging;
  final material.VoidCallback onFocusCanvas;
  final material.VoidCallback onDragStart;
  final void Function(material.Offset screenDelta) onDragMove;
  final material.VoidCallback onDragEnd;
  final material.VoidCallback onDragCancel;
  final material.VoidCallback onEdit;
  final void Function(ErdNote Function(ErdNote) change) onChange;
  final material.VoidCallback onAttachNearest;
  final material.VoidCallback onDelete;
  final void Function(material.Offset screenDelta) onResize;
  final material.VoidCallback onResizeEnd;

  /// Shadows read only on light surfaces, so a dark canvas gets twice the alpha.
  static double _shadowAlpha(material.Color canvas) =>
      canvas.computeLuminance() < 0.5 ? 0.24 : 0.12;

  @override
  material.Widget build(material.BuildContext context) {
    final n = note;
    final wb = context.workbench;
    final color = n.color == null ? null : slotColor(n.color!);
    final lines = parseErdNote(n.text);
    final base = material.TextStyle(
        fontSize: 12, color: Theme.of(context).colorScheme.foreground);
    return material.Positioned(
      left: n.x,
      top: n.y,
      width: n.width,
      height: n.height,
      child: ContextMenu(
        items: [
          MenuButton(
            key: material.ValueKey('erd_note_edit_${n.id}'),
            onPressed: (_) => onEdit(),
            child: const Text('Edit note…'),
          ),
          MenuButton(
            subMenu: [
              MenuButton(
                onPressed: (_) => onChange((o) => o.copyWith(color: () => null)),
                child: const Text('None'),
              ),
              for (var i = 0; i < erdHeaderSlots.length; i++)
                MenuButton(
                  leading: material.Icon(material.Icons.circle,
                      size: 12, color: slotColor(erdHeaderSlots[i])),
                  onPressed: (_) => onChange(
                      (o) => o.copyWith(color: () => erdHeaderSlots[i])),
                  child: Text('Colour ${i + 1}'),
                ),
            ],
            child: const Text('Colour'),
          ),
          if (n.attachedTo == null)
            MenuButton(
              key: material.ValueKey('erd_note_attach_${n.id}'),
              onPressed: (_) => onAttachNearest(),
              child: const Text('Attach to nearest table'),
            )
          else
            MenuButton(
              key: material.ValueKey('erd_note_detach_${n.id}'),
              onPressed: (_) =>
                  onChange((o) => o.copyWith(attachedTo: () => null)),
              child: Text('Detach from ${n.attachedTo}'),
            ),
          MenuButton(
            key: material.ValueKey('erd_note_delete_${n.id}'),
            onPressed: (_) => onDelete(),
            child: const Text('Delete note'),
          ),
        ],
        child: material.Stack(
          children: [
            material.Positioned.fill(
              child: material.MouseRegion(
                cursor: dragging
                    ? material.SystemMouseCursors.grabbing
                    : material.SystemMouseCursors.grab,
                child: material.GestureDetector(
                  key: material.ValueKey('erd_note_${n.id}'),
                  dragStartBehavior: DragStartBehavior.down,
                  // Esc, zoom and search keys work after touching a note.
                  onTapDown: (_) => onFocusCanvas(),
                  onPanStart: (_) {
                    onFocusCanvas();
                    onDragStart();
                  },
                  onPanUpdate: (d) => onDragMove(d.delta),
                  onPanEnd: (_) => onDragEnd(),
                  onPanCancel: onDragCancel,
                  onDoubleTap: onEdit,
                  child: material.DecoratedBox(
                    decoration: material.BoxDecoration(
                      // Not the canvas colour: a plain note is a slightly
                      // darker sheet with a shadow, like the cards.
                      color: material.Color.alphaBlend(
                          (color ?? wb.mutedForeground).withValues(
                              alpha: color == null ? tint : 0.18),
                          wb.surface),
                      borderRadius: material.BorderRadius.circular(6),
                      border: material.Border.all(
                          color: color ?? wb.borderSubtle,
                          width: n.attachedTo == null ? 1 : 1.5),
                      boxShadow: [
                        material.BoxShadow(
                          color: wb.shadow
                              .withValues(alpha: _shadowAlpha(wb.canvas)),
                          blurRadius: dragging ? 14 : 6,
                          offset: material.Offset(0, dragging ? 5 : 2),
                        ),
                      ],
                    ),
                    child: material.ClipRect(
                      child: material.Padding(
                        padding: const material.EdgeInsets.all(8),
                        child: material.SingleChildScrollView(
                          physics: const material.NeverScrollableScrollPhysics(),
                          child: material.Column(
                            crossAxisAlignment: material.CrossAxisAlignment.start,
                            children: [
                              for (final line in lines)
                                material.Text.rich(
                                  material.TextSpan(
                                    style: base,
                                    children: [
                                      if (line.bullet)
                                        const material.TextSpan(text: '•  '),
                                      for (final r in line.runs)
                                        material.TextSpan(
                                          text: r.text,
                                          style: r.bold
                                              ? const material.TextStyle(
                                                  fontWeight:
                                                      material.FontWeight.w700)
                                              : null,
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            material.Positioned(
              right: 0,
              bottom: 0,
              width: 16,
              height: 16,
              child: material.MouseRegion(
                cursor: material.SystemMouseCursors.resizeDownRight,
                child: material.GestureDetector(
                  key: material.ValueKey('erd_note_resize_${n.id}'),
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: (_) => onFocusCanvas(),
                  onPanUpdate: (d) => onResize(d.delta),
                  onPanEnd: (_) => onResizeEnd(),
                  child: material.Icon(material.Icons.drag_handle_rounded,
                      size: 12, color: wb.mutedForeground),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
