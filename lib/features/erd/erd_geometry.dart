import 'dart:ui' show Offset;

/// Edge drawing shared by the screen painter and the SVG export, so both draw
/// the same rounded corners and the same end markers.
abstract final class ErdGeometry {
  /// Corner rounding in logical px.
  static const double cornerRadius = 8;

  /// Every interior corner of [pts] as (before, corner, after): the polyline
  /// turns at [corner], and the turn is rounded between [before] and [after].
  static List<(Offset, Offset, Offset)> corners(
    List<Offset> pts, {
    double radius = cornerRadius,
  }) {
    final out = <(Offset, Offset, Offset)>[];
    for (var i = 1; i < pts.length - 1; i++) {
      final a = pts[i - 1], b = pts[i], c = pts[i + 1];
      final r = [radius, (b - a).distance / 2, (c - b).distance / 2]
          .reduce((x, y) => x < y ? x : y);
      final inDir = _dir(a, b), outDir = _dir(b, c);
      out.add((b - inDir * r, b, b + outDir * r));
    }
    return out;
  }

  /// "Many" end at the FK card: three prongs meeting 12 px out from [edge].
  static List<(Offset, Offset)> crowFoot(Offset edge, Offset next) {
    final d = _dir(edge, next);
    final n = Offset(-d.dy, d.dx);
    final tip = edge + d * 12;
    return [(tip, edge + n * 6), (tip, edge - n * 6), (tip, edge)];
  }

  /// A bar across the line [distance] px out from [edge]: "one" end at the
  /// referenced card, and the mandatory side of a foreign key.
  static (Offset, Offset) oneBar(Offset edge, Offset prev, {double distance = 8}) {
    final d = _dir(edge, prev);
    final n = Offset(-d.dy, d.dx);
    final at = edge + d * distance;
    return (at + n * 6, at - n * 6);
  }

  /// Circle that marks the optional side of a foreign key ("zero"), beyond
  /// the crow's foot prongs: its centre and radius.
  static (Offset, double) optionalCircle(Offset edge, Offset next) {
    final d = _dir(edge, next);
    return (edge + d * 17, 4);
  }

  /// Distance from [p] to the polyline [pts] (straight segments, no corner
  /// rounding). Infinity for a route with fewer than two points.
  static double distanceToRoute(List<Offset> pts, Offset p) {
    var best = double.infinity;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      final t = len2 == 0
          ? 0.0
          : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
      final nearest = a + ab * t.toDouble();
      final dist = (p - nearest).distance;
      if (dist < best) best = dist;
    }
    return best;
  }

  static Offset _dir(Offset from, Offset to) {
    final v = to - from;
    final len = v.distance;
    return len == 0 ? const Offset(1, 0) : v / len;
  }
}
