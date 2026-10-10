import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_geometry.dart';
import 'package:querya_desktop/core/erd/erd_router.dart';

/// Draws the relations of the diagram: rounded polylines with crow's feet and
/// cardinality markers.
class ErdRelationPainter extends material.CustomPainter {
  ErdRelationPainter({
    required this.routes,
    required this.color,
    required this.highlight,
    required this.focus,
    this.picked,
  });

  final List<ErdRoute> routes;
  final material.Color color;
  final material.Color highlight;

  /// Table whose relations are drawn on top in [highlight].
  final String? focus;

  /// A relation picked by a click: only it is drawn in [highlight] (#1281).
  final ErdRelation? picked;

  bool get _anyFocus => picked != null || focus != null;

  bool _focused(ErdRoute r) {
    final p = picked;
    if (p != null) return r.relation.sameAs(p);
    return focus != null &&
        (r.relation.fromTable == focus || r.relation.toTable == focus);
  }

  void _label(material.Canvas canvas, String text, material.Offset at,
      material.Color c) {
    final tp = material.TextPainter(
      text: material.TextSpan(
          text: text,
          style: material.TextStyle(
              fontSize: 10, color: c, fontWeight: material.FontWeight.w600)),
      textDirection: material.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - material.Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  void paint(material.Canvas canvas, material.Size size) {
    // Others first, focused on top.
    for (final pass in [false, true]) {
      for (final r in routes) {
        if (_focused(r) != pass || r.points.length < 2) continue;
        final paint = material.Paint()
          ..color = pass
              ? highlight
              : color.withValues(alpha: _anyFocus ? 0.35 : 0.85)
          ..style = material.PaintingStyle.stroke
          ..strokeWidth = pass ? 2 : 1.4
          ..strokeCap = material.StrokeCap.round
          ..strokeJoin = material.StrokeJoin.round;
        canvas.drawPath(roundedPath(r.points), paint);
        // FK end: a crow's foot ("many"), or a bar when the FK column is
        // unique on its own ("one", #1281).
        if (r.relation.oneToOne) {
          final (oa, ob) = ErdGeometry.oneBar(r.points[0], r.points[1]);
          canvas.drawLine(oa, ob, paint);
        } else {
          for (final (a, b)
              in ErdGeometry.crowFoot(r.points[0], r.points[1])) {
            canvas.drawLine(a, b, paint);
          }
        }
        // FK side: a circle when the column may be NULL ("zero or many"), a
        // bar otherwise ("one or many").
        if (r.relation.optional) {
          final (c, radius) =
              ErdGeometry.optionalCircle(r.points[0], r.points[1]);
          canvas.drawCircle(c, radius, paint);
        } else {
          final (fa, fb) =
              ErdGeometry.oneBar(r.points[0], r.points[1], distance: 17);
          canvas.drawLine(fa, fb, paint);
        }
        final (barA, barB) =
            ErdGeometry.oneBar(r.points.last, r.points[r.points.length - 2]);
        canvas.drawLine(barA, barB, paint);
        // Cardinality labels, as dbdiagram writes them.
        _label(canvas, r.relation.oneToOne ? '1' : '*',
            ErdGeometry.endLabel(r.points[0], r.points[1]), paint.color);
        _label(
            canvas,
            '1',
            ErdGeometry.endLabel(
                r.points.last, r.points[r.points.length - 2]),
            paint.color);
      }
    }
  }

  /// Edges take no pointer: a CustomPaint is hit everywhere by default, which
  /// hid the pointer from the hover layer below and so the edge label never
  /// showed.
  @override
  bool? hitTest(material.Offset position) => false;

  @override
  bool shouldRepaint(ErdRelationPainter old) =>
      old.routes != routes ||
      old.color != color ||
      old.highlight != highlight ||
      old.focus != focus ||
      old.picked != picked;
}

/// Polyline with corners rounded by up to 8 px.
material.Path roundedPath(List<material.Offset> pts, {double radius = 8}) {
  final path = material.Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final (p1, corner, p2) in ErdGeometry.corners(pts, radius: radius)) {
    path
      ..lineTo(p1.dx, p1.dy)
      ..quadraticBezierTo(corner.dx, corner.dy, p2.dx, p2.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}
