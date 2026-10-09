import 'dart:math' show max, min;
import 'dart:ui' show Offset, Size;

import 'package:querya_desktop/features/erd/erd_geometry.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/features/erd/erd_model.dart';
import 'package:querya_desktop/features/erd/erd_router.dart';

/// Text exports of an [ErdSchema].
class ErdExport {
  ErdExport._();

  /// Longest side of a PNG export, in pixels.
  static const int pngMaxSide = 8192;

  // Rough glyph widths for the SVG text fitting: sans-serif at 12 px and 10 px.
  static const double _nameCharPx = 7.5;
  static const double _typeCharPx = 6.0;

  static String _id(String s) {
    final r = s.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    return r.isEmpty ? '_' : r;
  }

  /// Mermaid.js `erDiagram` source.
  static String toMermaid(ErdSchema schema) {
    final b = StringBuffer('erDiagram\n');
    for (final t in schema.tables) {
      b.writeln('  ${_id(t.name)} {');
      for (final c in t.columns) {
        final keys = [
          if (c.isPrimaryKey) 'PK',
          if (c.isForeignKey) 'FK',
        ].join(',');
        final type = c.type.trim().isEmpty ? 'unknown' : _id(c.type.trim());
        b.writeln('    $type ${_id(c.name)}${keys.isEmpty ? '' : ' $keys'}');
      }
      b.writeln('  }');
    }
    for (final r in schema.relations) {
      b.writeln(
          '  ${_id(r.toTable)} ||--o{ ${_id(r.fromTable)} : "${r.fromColumn.replaceAll('"', '')}"');
    }
    return b.toString();
  }

  /// Pixel ratio that keeps the longest side of a PNG of [size] within
  /// [maxSide]. Capped at 2, the on-screen density. Below 1 the image is
  /// rendered at reduced resolution.
  static double pngPixelRatio(Size size, {int maxSide = pngMaxSide}) {
    final longest = max(size.width, size.height);
    if (longest <= 0) return 2;
    return min(2.0, maxSide / longest);
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _n(double v) => v.toStringAsFixed(1);

  static String _p(Offset o) => '${_n(o.dx)} ${_n(o.dy)}';

  /// Shortens [s] with an ellipsis so it fits [avail] px at [charPx] per glyph.
  static String _fit(String s, double avail, double charPx) {
    if (s.length * charPx <= avail) return s;
    final keep = (avail / charPx).floor() - 1;
    if (keep < 1) return '…';
    return '${s.substring(0, keep)}…';
  }

  /// Route with the same corner rounding as the screen.
  static String _routePath(List<Offset> pts) {
    final d = StringBuffer('M ${_p(pts.first)}');
    for (final (p1, corner, p2) in ErdGeometry.corners(pts)) {
      d.write(' L ${_p(p1)} Q ${_p(corner)} ${_p(p2)}');
    }
    d.write(' L ${_p(pts.last)}');
    return d.toString();
  }

  /// PK or FK marker: a small coloured pill with its letters.
  static String _pill(double x, double rowTop, String label, String fill) =>
      '<rect x="${_n(x)}" y="${_n(rowTop + 3)}" width="18" height="12" rx="3" '
      'fill="$fill"/>'
      '<text x="${_n(x + 9)}" y="${_n(rowTop + 12)}" text-anchor="middle" '
      'font-size="8" font-weight="bold" fill="#ffffff">$label</text>';

  /// Standalone SVG rendering of the diagram, with the same positions and
  /// edge routes as the screen ([routes] defaults to a fresh routing).
  ///
  /// Like the screen, it draws rounded cards with a tinted header, a crow's
  /// foot at the FK end and a bar at the referenced end, PK and FK pills, and
  /// clips text to each card.
  static String toSvg(ErdSchema schema, ErdLayout layout, {List<ErdRoute>? routes}) {
    final size = layout.size;
    final w = _n(size.width), h = _n(size.height);
    final b = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" '
          'viewBox="0 0 $w $h" font-family="sans-serif" font-size="12">')
      ..writeln('<rect width="100%" height="100%" fill="#ffffff"/>');
    for (final r in routes ?? ErdRouter.route(schema, layout)) {
      if (r.points.length < 2) continue;
      final title = '${_esc(r.relation.fromTable)}.'
          '${_esc(r.relation.fromColumn)} → ${_esc(r.relation.toTable)}.'
          '${_esc(r.relation.toColumn)}';
      final ends = StringBuffer();
      for (final (a, c) in ErdGeometry.crowFoot(r.points[0], r.points[1])) {
        ends.write('M ${_p(a)} L ${_p(c)} ');
      }
      // FK side: a circle when the column may be NULL, a bar otherwise.
      String? circle;
      if (r.relation.optional) {
        final (centre, radius) =
            ErdGeometry.optionalCircle(r.points[0], r.points[1]);
        circle = '<circle cx="${_n(centre.dx)}" cy="${_n(centre.dy)}" '
            'r="${_n(radius)}" fill="#ffffff" stroke="#64748b" stroke-width="1.5"/>';
      } else {
        final (fa, fb) =
            ErdGeometry.oneBar(r.points[0], r.points[1], distance: 17);
        ends.write('M ${_p(fa)} L ${_p(fb)} ');
      }
      final (barA, barB) =
          ErdGeometry.oneBar(r.points.last, r.points[r.points.length - 2]);
      ends.write('M ${_p(barA)} L ${_p(barB)}');
      b
        ..writeln('<path d="${_routePath(r.points)}" fill="none" stroke="#64748b" '
            'stroke-width="1.5" stroke-linejoin="round"><title>$title</title></path>')
        ..writeln('<path d="$ends" fill="none" stroke="#64748b" stroke-width="1.5"/>');
      if (circle != null) b.writeln(circle);
    }
    for (var ti = 0; ti < schema.tables.length; ti++) {
      final t = schema.tables[ti];
      final rect = layout.rectOf(t);
      final left = rect.left, top = rect.top, cw = rect.width, ch = rect.height;
      final clip = 'card$ti';
      final inner = cw - 20;
      final typeAvail = inner * 0.4;
      b
        ..writeln('<clipPath id="$clip"><rect x="${_n(left)}" y="${_n(top)}" '
            'width="${_n(cw)}" height="${_n(ch)}" rx="6"/></clipPath>')
        ..writeln('<rect x="${_n(left)}" y="${_n(top)}" width="${_n(cw)}" '
            'height="${_n(ch)}" rx="6" fill="#f8fafc" stroke="#94a3b8"/>')
        ..writeln('<g clip-path="url(#$clip)">')
        ..writeln('<rect x="${_n(left)}" y="${_n(top)}" width="${_n(cw)}" '
            'height="${_n(ErdLayout.headerHeight)}" fill="#e0f2fe"/>')
        ..writeln('<text x="${_n(left + 10)}" y="${_n(top + 21)}" '
            'font-weight="bold">${_esc(_fit(t.name, inner, _nameCharPx))}</text>');
      for (var i = 0; i < t.columns.length; i++) {
        final c = t.columns[i];
        final rowTop = top + ErdLayout.headerHeight + ErdLayout.rowHeight * i;
        final baseline = rowTop + 15;
        var x = left + 10;
        if (c.isPrimaryKey) {
          b.writeln(_pill(x, rowTop, 'PK', '#2563eb'));
          x += 21;
        }
        if (c.isForeignKey) {
          b.writeln(_pill(x, rowTop, 'FK', '#0d9488'));
          x += 21;
        }
        final nameAvail = inner - (x - left - 10) - typeAvail - 6;
        b
          ..writeln('<text x="${_n(x)}" y="${_n(baseline)}"'
              '${c.isPrimaryKey ? ' font-weight="bold"' : ''}>'
              '${_esc(_fit(c.name, nameAvail, _nameCharPx))}</text>')
          ..writeln('<text x="${_n(left + cw - 10)}" y="${_n(baseline)}" '
              'text-anchor="end" font-size="10" fill="#64748b">'
              '${_esc(_fit(c.isNullable ? '${c.type}?' : c.type, typeAvail, _typeCharPx))}</text>');
      }
      b.writeln('</g>');
    }
    b.writeln('</svg>');
    return b.toString();
  }
}
