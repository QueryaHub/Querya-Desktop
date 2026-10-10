import 'dart:math' as math;
import 'dart:ui';

import 'package:querya_desktop/core/erd/erd_model.dart';

/// Geometry of the diagram: card sizes, positions and canvas extent.
///
/// Immutable; [withPosition] returns a copy with one card moved (drag).
class ErdLayout {
  ErdLayout._(this.positions, this._heights, this._widths);

  /// Width of a card with nothing wide in it, and the bounds of a card sized
  /// to its content ([widthOf]).
  static const double cardWidth = 220;
  static const double minCardWidth = 160;
  static const double maxCardWidth = 360;
  static const double headerHeight = 34;
  static const double rowHeight = 22;
  static const double margin = 40;

  /// Horizontal gap between layers: room for the edge tracks.
  static const double layerGap = 110;

  /// Vertical gap between cards of one layer.
  static const double cardGap = 44;

  final Map<String, Offset> positions;
  final Map<String, double> _heights;
  final Map<String, double> _widths;

  static double cardHeight(ErdTable t) =>
      headerHeight + rowHeight * t.columns.length + 6;

  // Glyph widths the card's text needs, a little generous so the estimate is
  // never short: the header is 13 px semibold, names 12 px, types 10 px mono.
  static const double _headerCharPx = 8.0;
  static const double _nameCharPx = 7.0;
  static const double _typeCharPx = 6.3;

  /// Width that shows [t]'s name and every `column  type` row without cutting
  /// them, between [minCardWidth] and [maxCardWidth] (#1276).
  static double widthOf(ErdTable t) {
    // Padding 10 + icon 14 + gap 6, name, gap 6, column count, padding 10.
    var w = 46 + t.name.length * _headerCharPx +
        '${t.columns.length}'.length * _typeCharPx +
        (t.isJunction ? 24 : 0);
    for (final c in t.columns) {
      final type = c.isNullable ? '${c.type}?' : c.type;
      // Padding 10 + marker slot 26, name, gap 8, type, padding 10.
      final row = 54 +
          c.name.length * _nameCharPx +
          type.length * _typeCharPx +
          c.badges.length * 18;
      if (row > w) w = row;
    }
    return w.clamp(minCardWidth, maxCardWidth).ceilToDouble();
  }

  /// Width of the card of [table] in this layout.
  double widthFor(String table) => _widths[table] ?? cardWidth;

  /// Rect of a table card.
  Rect rectOf(ErdTable t) =>
      positions[t.name]! & Size(widthFor(t.name), cardHeight(t));

  /// Canvas extent: every card plus a margin.
  Size get size {
    var w = margin * 2, h = margin * 2;
    positions.forEach((name, p) {
      w = math.max(w, p.dx + widthFor(name) + margin);
      h = math.max(h, p.dy + (_heights[name] ?? 0) + margin);
    });
    return Size(w, h);
  }

  /// Zoom that fits [content] into [viewport] with a 24 px margin, never
  /// enlarged. It may go below the usual minimum zoom of the view, so a
  /// diagram of a few hundred tables still fits.
  static double fitScale(Size content, Size viewport) {
    const pad = 24.0;
    if (content.width <= 0 || content.height <= 0) return 1;
    final s = math.min((viewport.width - 2 * pad) / content.width,
        (viewport.height - 2 * pad) / content.height);
    return s.clamp(0.02, 1.0).toDouble();
  }

  /// Vertical center of [column] inside [t]'s card (header when unknown).
  double columnY(ErdTable t, String column) {
    final i = t.columns.indexWhere((c) => c.name == column);
    final top = positions[t.name]!.dy;
    if (i < 0) return top + headerHeight / 2;
    return top + headerHeight + rowHeight * i + rowHeight / 2;
  }

  /// Space between a group's frame and its cards, and the frame's title band
  /// above them (#1282). Both fit in [margin].
  static const double framePadding = 12;
  static const double frameTitleHeight = 24;

  /// The frame around [tables] (those in this layout): their cards' bounds
  /// with [framePadding] and the title band on top; null when none is here.
  Rect? frameOf(Iterable<String> tables) {
    Rect? box;
    for (final t in tables) {
      final p = positions[t];
      if (p == null) continue;
      final r = p & Size(widthFor(t), _heights[t] ?? headerHeight);
      box = box == null ? r : box.expandToInclude(r);
    }
    if (box == null) return null;
    return Rect.fromLTRB(
      box.left - framePadding,
      box.top - framePadding - frameTitleHeight,
      box.right + framePadding,
      box.bottom + framePadding,
    );
  }

  /// Whether the frame of [members] covers a card that is not one of them.
  bool frameCoversOthers(Iterable<String> members) {
    final set = members.toSet();
    final frame = frameOf(set);
    if (frame == null) return false;
    for (final e in positions.entries) {
      if (set.contains(e.key)) continue;
      final r = e.value & Size(widthFor(e.key), _heights[e.key] ?? headerHeight);
      if (frame.overlaps(r)) return true;
    }
    return false;
  }

  /// Gap between the cards of a gathered group.
  static const double gatherGapX = 60;

  /// Copy with the cards of [members] packed into one block, so their frame
  /// covers no other card (#1282).
  ///
  /// The cards keep their reading order (top to bottom, left to right) in a
  /// near-square grid. The block goes where the first of the members was, or
  /// at the next member's place, and if none is free, to the right of every
  /// other card. Cards that are not members never move.
  ErdLayout gather(Iterable<String> members) {
    final names = [for (final m in members) if (positions.containsKey(m)) m]
      ..sort((a, b) {
        final pa = positions[a]!, pb = positions[b]!;
        final c = pa.dy.compareTo(pb.dy);
        return c != 0 ? c : pa.dx.compareTo(pb.dx);
      });
    if (names.length < 2) return this;
    final set = names.toSet();
    final cols = math.sqrt(names.length).ceil();
    final rows = (names.length / cols).ceil();
    final colWidth = List<double>.filled(cols, 0);
    final rowHeight = List<double>.filled(rows, 0);
    for (var i = 0; i < names.length; i++) {
      colWidth[i % cols] = math.max(colWidth[i % cols], widthFor(names[i]));
      rowHeight[i ~/ cols] = math.max(
          rowHeight[i ~/ cols], _heights[names[i]] ?? headerHeight);
    }
    // Offsets of each card inside the block.
    final colX = <double>[0];
    for (var c = 0; c < cols - 1; c++) {
      colX.add(colX.last + colWidth[c] + gatherGapX);
    }
    final rowY = <double>[0];
    for (var r = 0; r < rows - 1; r++) {
      rowY.add(rowY.last + rowHeight[r] + cardGap);
    }
    final blockW = colX.last + colWidth.last;
    final blockH = rowY.last + rowHeight.last;

    final others = [
      for (final e in positions.entries)
        if (!set.contains(e.key))
          (e.value & Size(widthFor(e.key), _heights[e.key] ?? headerHeight))
              .inflate(8),
    ];
    // The block's frame, with room for its padding and title band.
    bool free(Offset o) {
      final frame = Rect.fromLTWH(
        o.dx - framePadding,
        o.dy - framePadding - frameTitleHeight,
        blockW + 2 * framePadding,
        blockH + 2 * framePadding + frameTitleHeight,
      );
      return !others.any(frame.overlaps);
    }

    const minX = framePadding + 8;
    const minY = frameTitleHeight + framePadding + 8;
    Offset clamp(Offset o) =>
        Offset(math.max(minX, o.dx), math.max(minY, o.dy));
    var origin = positions[names.first]!;
    var placed = false;
    for (final n in names) {
      final o = clamp(positions[n]!);
      if (free(o)) {
        origin = o;
        placed = true;
        break;
      }
    }
    if (!placed) {
      var right = 0.0;
      for (final e in positions.entries) {
        if (set.contains(e.key)) continue;
        right = math.max(right, e.value.dx + widthFor(e.key));
      }
      origin = clamp(Offset(right + layerGap, positions[names.first]!.dy));
    }
    return withPositions({
      for (var i = 0; i < names.length; i++)
        names[i]: origin + Offset(colX[i % cols], rowY[i ~/ cols]),
    });
  }

  /// Copy with every table of [moves] at its new top-left, as
  /// [withPosition] places one.
  ErdLayout withPositions(Map<String, Offset> moves) {
    final next = Map<String, Offset>.of(positions);
    moves.forEach((table, topLeft) {
      next[table] = Offset(math.max(8, topLeft.dx), math.max(8, topLeft.dy));
    });
    return ErdLayout._(next, _heights, _widths);
  }

  /// Copy with [table] moved to [topLeft] (kept inside the canvas origin).
  ErdLayout withPosition(String table, Offset topLeft) {
    final next = Map<String, Offset>.of(positions);
    next[table] = Offset(math.max(8, topLeft.dx), math.max(8, topLeft.dy));
    return ErdLayout._(next, _heights, _widths);
  }

  /// Layered layout: a referenced table sits in a layer left of the tables
  /// that reference it; inside a layer, cards are ordered by the average
  /// position of their neighbours to reduce crossings. Tables without
  /// relations go into a grid below.
  ///
  /// [measure] gives a card's width; the screen passes one that measures the
  /// text with the card's own fonts (`ErdCardMeasure`), exports and tests may
  /// rely on the glyph estimate of [widthOf].
  ///
  /// [groups] keep their tables together (#1282): each group, and the tables
  /// in none, is laid out on its own as a block, and the blocks are packed in
  /// rows. A table goes with the first group that names it.
  factory ErdLayout.compute(
    ErdSchema schema, {
    double Function(ErdTable table)? measure,
    List<Iterable<String>> groups = const [],
  }) {
    final known = {for (final t in schema.tables) t.name};
    final claimed = <String>{};
    final blocks = <Set<String>>[
      for (final g in groups)
        {for (final t in g) if (known.contains(t) && claimed.add(t)) t},
    ]..removeWhere((b) => b.isEmpty);
    if (blocks.isEmpty) return ErdLayout._layered(schema, measure);
    final rest = {for (final t in known) if (!claimed.contains(t)) t};
    return ErdLayout._packed(
      [
        for (final b in [if (rest.isNotEmpty) rest, ...blocks])
          ErdLayout._layered(_subset(schema, b), measure),
      ],
    );
  }

  static ErdSchema _subset(ErdSchema schema, Set<String> tables) => ErdSchema(
        tables: [
          for (final t in schema.tables)
            if (tables.contains(t.name)) t,
        ],
        relations: [
          for (final r in schema.relations)
            if (tables.contains(r.fromTable) && tables.contains(r.toTable)) r,
        ],
      );

  /// [parts] side by side in rows about as wide as the whole is tall. Each
  /// part keeps its own margin, so frames of neighbouring blocks never meet.
  factory ErdLayout._packed(List<ErdLayout> parts) {
    final area = parts.fold<double>(
        0, (s, p) => s + p.size.width * p.size.height);
    final rowWidth = math.max(
      parts.map((p) => p.size.width).reduce(math.max),
      math.sqrt(area) * 1.6,
    );
    final positions = <String, Offset>{};
    final heights = <String, double>{};
    final widths = <String, double>{};
    var x = 0.0, y = 0.0, rowHeight = 0.0;
    for (final part in parts) {
      final size = part.size;
      if (x > 0 && x + size.width > rowWidth) {
        x = 0;
        y += rowHeight;
        rowHeight = 0;
      }
      part.positions.forEach((n, p) => positions[n] = p.translate(x, y));
      heights.addAll(part._heights);
      widths.addAll(part._widths);
      x += size.width;
      rowHeight = math.max(rowHeight, size.height);
    }
    return ErdLayout._(positions, heights, widths);
  }

  factory ErdLayout._layered(
    ErdSchema schema,
    double Function(ErdTable table)? measure,
  ) {
    final names = [for (final t in schema.tables) t.name];
    final byName = {for (final t in schema.tables) t.name: t};
    final heights = {for (final t in schema.tables) t.name: cardHeight(t)};
    final width = measure ?? widthOf;
    final widths = {for (final t in schema.tables) t.name: width(t)};
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
    // A layer is as wide as its widest card; the next one starts after it.
    var x = margin;
    for (var i = 0; i < layers.length; i++) {
      var y = margin + (tallest - columnHeight(layers[i])) / 2;
      for (final n in layers[i]) {
        positions[n] = Offset(x, y);
        y += heights[n]! + cardGap;
      }
      x += layers[i].map((n) => widths[n]!).reduce(math.max) + layerGap;
    }

    if (isolated.isNotEmpty) {
      final perRow = math.max(
          math.max(1, layers.length), math.sqrt(isolated.length).ceil());
      var y = layers.isEmpty ? margin : margin + tallest + cardGap * 2;
      for (var i = 0; i < isolated.length; i += perRow) {
        final row = isolated.sublist(i, math.min(i + perRow, isolated.length));
        var rx = margin;
        for (var j = 0; j < row.length; j++) {
          positions[row[j]] = Offset(rx, y);
          rx += widths[row[j]]! + cardGap;
        }
        y += row.map((n) => heights[n]!).reduce(math.max) + cardGap;
      }
    }
    assert(positions.length == byName.length);
    return ErdLayout._(positions, heights, widths);
  }
}
