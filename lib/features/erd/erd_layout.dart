import 'dart:math' as math;
import 'dart:ui';

import 'package:querya_desktop/features/erd/erd_model.dart';

/// Geometry of the diagram: card sizes, positions and canvas extent.
class ErdLayout {
  ErdLayout._(this.positions, this.size);

  static const double cardWidth = 220;
  static const double headerHeight = 32;
  static const double rowHeight = 22;
  static const double gap = 60;

  final Map<String, Offset> positions;
  final Size size;

  static double cardHeight(ErdTable t) =>
      headerHeight + rowHeight * t.columns.length + 6;

  /// Rect of a table card.
  Rect rectOf(ErdTable t) =>
      positions[t.name]! & Size(cardWidth, cardHeight(t));

  /// Vertical center of [column] inside [t]'s card (header when unknown).
  double columnY(ErdTable t, String column) {
    final i = t.columns.indexWhere((c) => c.name == column);
    final top = positions[t.name]!.dy;
    if (i < 0) return top + headerHeight / 2;
    return top + headerHeight + rowHeight * i + rowHeight / 2;
  }

  /// Grid layout; tables are ordered so related ones sit next to each other.
  factory ErdLayout.compute(ErdSchema schema) {
    final byName = {for (final t in schema.tables) t.name: t};
    final adj = <String, Set<String>>{
      for (final t in schema.tables) t.name: <String>{},
    };
    for (final r in schema.relations) {
      adj[r.fromTable]?.add(r.toTable);
      adj[r.toTable]?.add(r.fromTable);
    }
    final ordered = <ErdTable>[];
    final seen = <String>{};
    final roots = schema.tables.toList()
      ..sort((a, b) => adj[b.name]!.length.compareTo(adj[a.name]!.length));
    for (final root in roots) {
      if (!seen.add(root.name)) continue;
      final queue = [root.name];
      while (queue.isNotEmpty) {
        final cur = queue.removeAt(0);
        ordered.add(byName[cur]!);
        final next = adj[cur]!.toList()..sort();
        for (final n in next) {
          if (seen.add(n)) queue.add(n);
        }
      }
    }

    final perRow = math.max(1, math.sqrt(ordered.length).ceil());
    final positions = <String, Offset>{};
    var x = gap;
    var y = gap;
    var rowMaxH = 0.0;
    var maxX = 0.0;
    for (var i = 0; i < ordered.length; i++) {
      if (i > 0 && i % perRow == 0) {
        x = gap;
        y += rowMaxH + gap;
        rowMaxH = 0;
      }
      final t = ordered[i];
      positions[t.name] = Offset(x, y);
      rowMaxH = math.max(rowMaxH, cardHeight(t));
      x += cardWidth + gap;
      maxX = math.max(maxX, x);
    }
    return ErdLayout._(
      positions,
      Size(math.max(maxX, gap * 2), y + rowMaxH + gap),
    );
  }
}
