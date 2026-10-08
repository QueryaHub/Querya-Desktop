import 'dart:math' as math;
import 'dart:ui';

import 'package:querya_desktop/features/erd/erd_model.dart';

/// Geometry of the diagram: card sizes, positions and canvas extent.
///
/// Immutable; [withPosition] returns a copy with one card moved (drag).
class ErdLayout {
  ErdLayout._(this.positions, this._heights);

  static const double cardWidth = 220;
  static const double headerHeight = 34;
  static const double rowHeight = 22;
  static const double margin = 40;

  /// Horizontal gap between layers: room for the edge tracks.
  static const double layerGap = 110;

  /// Vertical gap between cards of one layer.
  static const double cardGap = 44;

  final Map<String, Offset> positions;
  final Map<String, double> _heights;

  static double cardHeight(ErdTable t) =>
      headerHeight + rowHeight * t.columns.length + 6;

  /// Rect of a table card.
  Rect rectOf(ErdTable t) =>
      positions[t.name]! & Size(cardWidth, cardHeight(t));

  /// Canvas extent: every card plus a margin.
  Size get size {
    var w = margin * 2, h = margin * 2;
    positions.forEach((name, p) {
      w = math.max(w, p.dx + cardWidth + margin);
      h = math.max(h, p.dy + (_heights[name] ?? 0) + margin);
    });
    return Size(w, h);
  }

  /// Vertical center of [column] inside [t]'s card (header when unknown).
  double columnY(ErdTable t, String column) {
    final i = t.columns.indexWhere((c) => c.name == column);
    final top = positions[t.name]!.dy;
    if (i < 0) return top + headerHeight / 2;
    return top + headerHeight + rowHeight * i + rowHeight / 2;
  }

  /// Copy with [table] moved to [topLeft] (kept inside the canvas origin).
  ErdLayout withPosition(String table, Offset topLeft) {
    final next = Map<String, Offset>.of(positions);
    next[table] = Offset(math.max(8, topLeft.dx), math.max(8, topLeft.dy));
    return ErdLayout._(next, _heights);
  }

  /// Layered layout: a referenced table sits in a layer left of the tables
  /// that reference it; inside a layer, cards are ordered by the average
  /// position of their neighbours to reduce crossings. Tables without
  /// relations go into a grid below.
  factory ErdLayout.compute(ErdSchema schema) {
    final names = [for (final t in schema.tables) t.name];
    final byName = {for (final t in schema.tables) t.name: t};
    final heights = {for (final t in schema.tables) t.name: cardHeight(t)};
    final neighbours = {for (final n in names) n: <String>{}};
    for (final r in schema.relations) {
      if (r.fromTable == r.toTable) continue;
      neighbours[r.fromTable]!.add(r.toTable);
      neighbours[r.toTable]!.add(r.fromTable);
    }
    final related = [for (final n in names) if (neighbours[n]!.isNotEmpty) n];
    final isolated = [for (final n in names) if (neighbours[n]!.isEmpty) n];

    // Longest-path layering; the cap breaks cycles.
    final layer = {for (final n in related) n: 0};
    final cap = math.max(0, related.length - 1);
    for (var pass = 0; pass < related.length; pass++) {
      var changed = false;
      for (final r in schema.relations) {
        if (r.fromTable == r.toTable) continue;
        final want = math.min(cap, layer[r.toTable]! + 1);
        if (layer[r.fromTable]! < want) {
          layer[r.fromTable] = want;
          changed = true;
        }
      }
      if (!changed) break;
    }
    final layerCount =
        related.isEmpty ? 0 : layer.values.reduce(math.max) + 1;
    final layers = [
      for (var i = 0; i < layerCount; i++)
        [for (final n in related) if (layer[n] == i) n],
    ]..removeWhere((l) => l.isEmpty);

    // Barycenter sweeps.
    Map<String, double> rank() => {
          for (final l in layers)
            for (var i = 0; i < l.length; i++) l[i]: i / math.max(1, l.length - 1),
        };
    for (var sweep = 0; sweep < 4; sweep++) {
      final r = rank();
      for (final l in layers) {
        final bary = {
          for (final n in l)
            n: neighbours[n]!.isEmpty
                ? r[n]!
                : neighbours[n]!.map((m) => r[m]!).reduce((a, b) => a + b) /
                    neighbours[n]!.length,
        };
        l.sort((a, b) {
          final c = bary[a]!.compareTo(bary[b]!);
          return c != 0 ? c : names.indexOf(a).compareTo(names.indexOf(b));
        });
      }
    }

    double columnHeight(List<String> l) =>
        l.fold<double>(0, (s, n) => s + heights[n]!) +
        cardGap * math.max(0, l.length - 1);
    final tallest = layers.isEmpty ? 0.0 : layers.map(columnHeight).reduce(math.max);

    final positions = <String, Offset>{};
    for (var i = 0; i < layers.length; i++) {
      final x = margin + i * (cardWidth + layerGap);
      var y = margin + (tallest - columnHeight(layers[i])) / 2;
      for (final n in layers[i]) {
        positions[n] = Offset(x, y);
        y += heights[n]! + cardGap;
      }
    }

    if (isolated.isNotEmpty) {
      final perRow = math.max(
          math.max(1, layers.length), math.sqrt(isolated.length).ceil());
      var y = layers.isEmpty ? margin : margin + tallest + cardGap * 2;
      for (var i = 0; i < isolated.length; i += perRow) {
        final row = isolated.sublist(i, math.min(i + perRow, isolated.length));
        for (var j = 0; j < row.length; j++) {
          positions[row[j]] = Offset(margin + j * (cardWidth + cardGap), y);
        }
        y += row.map((n) => heights[n]!).reduce(math.max) + cardGap;
      }
    }
    assert(positions.length == byName.length);
    return ErdLayout._(positions, heights);
  }
}
