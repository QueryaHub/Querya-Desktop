import 'dart:math' show max;
import 'dart:ui' show Offset;

import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';

/// Operations on the sticky notes of a diagram as plain functions (#1362), so
/// the placement, drag and resize rules can be tested without a widget tree.
abstract final class ErdNoteOps {
  /// The id for a new note: the first `n<number>` no note has.
  static String nextId(List<ErdNote> notes) {
    var n = 1;
    while (notes.any((o) => o.id == 'n$n')) {
      n++;
    }
    return 'n$n';
  }

  /// A new note holding [text], centred on [centre] (canvas space) but never
  /// closer than 8 px to the canvas origin.
  static ErdNote create(
    List<ErdNote> notes, {
    required String text,
    required Offset centre,
  }) =>
      ErdNote(
        id: nextId(notes),
        text: text,
        x: max(8.0, centre.dx - ErdNote.defaultWidth / 2),
        y: max(8.0, centre.dy - ErdNote.defaultHeight / 2),
      );

  /// [note] moved by [screenDelta] at zoom [scale], kept on the canvas.
  static ErdNote moved(ErdNote note, Offset screenDelta, double scale) {
    final d = screenDelta / (scale == 0 ? 1 : scale);
    return note.copyWith(x: max(0.0, note.x + d.dx), y: max(0.0, note.y + d.dy));
  }

  /// [note] resized by [screenDelta] at zoom [scale], not below its minimum.
  static ErdNote resized(ErdNote note, Offset screenDelta, double scale) {
    final d = screenDelta / (scale == 0 ? 1 : scale);
    return note.copyWith(
      width: max(ErdNote.minWidth, note.width + d.dx),
      height: max(ErdNote.minHeight, note.height + d.dy),
    );
  }

  /// The table of [visible] nearest to the middle of [note], to attach it to.
  static String? nearestTable(
    ErdNote note,
    ErdLayout layout,
    ErdSchema visible,
  ) {
    final c = Offset(note.x + note.width / 2, note.y + note.height / 2);
    String? best;
    var bestDistance = double.infinity;
    for (final t in visible.tables) {
      final d = (layout.rectOf(t).center - c).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = t.name;
      }
    }
    return best;
  }
}
