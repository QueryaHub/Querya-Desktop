import 'dart:math' show max, min;
import 'dart:ui' show Offset, Size;

import 'package:querya_desktop/features/erd/erd_geometry.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/features/erd/erd_router.dart';

/// Colours of the SVG export as `#rrggbb`. The defaults are a light theme;
/// the diagram view passes the colours of the current theme, so the file looks
/// like the screen.
class ErdSvgColors {
  const ErdSvgColors({
    this.background = '#ffffff',
    this.card = '#ffffff',
    this.border = '#cbd5e1',
    this.header = '#e8f1fd',
    this.text = '#0f172a',
    this.muted = '#64748b',
    this.edge = '#64748b',
    this.primaryKey = '#2563eb',
    this.foreignKey = '#0d9488',
  });

  final String background;
  final String card;
  final String border;

  /// Header band of a card (the accent over the card colour).
  final String header;
  final String text;

  /// Column types, the column count and the optional-end circle outline.
  final String muted;
  final String edge;
  final String primaryKey;
  final String foreignKey;

  /// `#rrggbb` for a 0xAARRGGBB colour value (alpha is dropped).
  static String hex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// Text exports of an [ErdSchema].
class ErdExport {
  ErdExport._();

  /// Longest side of a PNG export, in pixels.
  static const int pngMaxSide = 8192;

  // Rough glyph widths for the SVG text fitting: sans-serif at 12 px for
  // names, monospace at 10 px for types and the column count.
  static const double _nameCharPx = 7.5;
  static const double _typeCharPx = 6.0;

  /// Card corner radius, as on screen.
  static const double _cardRadius = 8;

  /// Width of one PK / FK pill and the gap after it.
  static const double _pillStep = 21;

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
    // The FK end as on screen: zero or many when the column may be NULL,
    // one or many otherwise.
    for (final r in schema.relations) {
      final many = r.optional ? 'o{' : '|{';
      b.writeln(
          '  ${_id(r.toTable)} ||--$many ${_id(r.fromTable)} : "${r.fromColumn.replaceAll('"', '')}"');
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
  /// Like the screen, it draws cards with an 8 px radius and a tinted header
  /// with the column count, a crow's foot at the FK end and a bar at the
  /// referenced end, PK and FK pills in a slot of the same width for every
  /// row of a card, monospace types, and clips text to each card. Every edge
  /// is an `erd-edge` path with a `<title>`, followed by its `erd-ends` path.
  static String toSvg(
    ErdSchema schema,
    ErdLayout layout, {
    List<ErdRoute>? routes,
    ErdSvgColors colors = const ErdSvgColors(),
    Map<String, String> headerFills = const {},
  }) {
    final size = layout.size;
    final w = _n(size.width), h = _n(size.height);
    final b = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" '
          'viewBox="0 0 $w $h" font-family="sans-serif" font-size="12" '
          'fill="${colors.text}">')
      ..writeln('<rect width="100%" height="100%" fill="${colors.background}"/>');
    for (final r in routes ?? ErdRouter.route(schema, layout)) {
      if (r.points.length < 2) continue;
      final title = '${_esc(r.relation.fromTable)}.'
          '${_esc(r.relation.fromColumn)} → ${_esc(r.relation.toTable)}.'
          '${_esc(r.relation.toColumn)}';
      final ends = StringBuffer();
      // FK end: a crow's foot ("many"), or a bar when the FK column is
      // unique on its own ("one", #1281).
      if (r.relation.oneToOne) {
        final (oa, ob) = ErdGeometry.oneBar(r.points[0], r.points[1]);
        ends.write('M ${_p(oa)} L ${_p(ob)} ');
      } else {
        for (final (a, c) in ErdGeometry.crowFoot(r.points[0], r.points[1])) {
          ends.write('M ${_p(a)} L ${_p(c)} ');
        }
      }
      // FK side: a circle when the column may be NULL, a bar otherwise.
      String? circle;
      if (r.relation.optional) {
        final (centre, radius) =
            ErdGeometry.optionalCircle(r.points[0], r.points[1]);
        circle = '<circle cx="${_n(centre.dx)}" cy="${_n(centre.dy)}" '
            'r="${_n(radius)}" fill="${colors.background}" '
            'stroke="${colors.edge}" stroke-width="1.5"/>';
      } else {
        final (fa, fb) =
            ErdGeometry.oneBar(r.points[0], r.points[1], distance: 17);
        ends.write('M ${_p(fa)} L ${_p(fb)} ');
      }
      final (barA, barB) =
          ErdGeometry.oneBar(r.points.last, r.points[r.points.length - 2]);
      ends.write('M ${_p(barA)} L ${_p(barB)}');
      b
        ..writeln('<path class="erd-edge" d="${_routePath(r.points)}" '
            'fill="none" stroke="${colors.edge}" stroke-width="1.5" '
            'stroke-linejoin="round"><title>$title</title></path>')
        ..writeln('<path class="erd-ends" d="$ends" fill="none" '
            'stroke="${colors.edge}" stroke-width="1.5"/>');
      if (circle != null) b.writeln(circle);
      final fkLabel = ErdGeometry.endLabel(r.points[0], r.points[1]);
      final refLabel = ErdGeometry.endLabel(
          r.points.last, r.points[r.points.length - 2]);
      b
        ..writeln('<text class="erd-end-label" x="${_n(fkLabel.dx)}" '
            'y="${_n(fkLabel.dy + 4)}" font-size="10" text-anchor="middle" '
            'fill="${colors.muted}">${r.relation.oneToOne ? '1' : '*'}</text>')
        ..writeln('<text class="erd-end-label" x="${_n(refLabel.dx)}" '
            'y="${_n(refLabel.dy + 4)}" font-size="10" text-anchor="middle" '
            'fill="${colors.muted}">1</text>');
    }
    final rx = _n(_cardRadius);
    for (var ti = 0; ti < schema.tables.length; ti++) {
      final t = schema.tables[ti];
      final rect = layout.rectOf(t);
      final left = rect.left, top = rect.top, cw = rect.width, ch = rect.height;
      final clip = 'card$ti';
      final inner = cw - 20;
      final typeAvail = inner * 0.4;
      // One slot width for every row, so the names of a card line up.
      var pills = 0;
      for (final c in t.columns) {
        final n = (c.isPrimaryKey ? 1 : 0) + (c.isForeignKey ? 1 : 0);
        if (n > pills) pills = n;
      }
      final slot = pills * _pillStep;
      final count = '${t.columns.length}';
      final countWidth = count.length * _typeCharPx + 8;
      b
        ..writeln('<clipPath id="$clip"><rect x="${_n(left)}" y="${_n(top)}" '
            'width="${_n(cw)}" height="${_n(ch)}" rx="$rx"/></clipPath>')
        ..writeln('<rect x="${_n(left)}" y="${_n(top)}" width="${_n(cw)}" '
            'height="${_n(ch)}" rx="$rx" fill="${colors.card}" '
            'stroke="${colors.border}"/>')
        ..writeln('<g clip-path="url(#$clip)">')
        ..writeln('<rect x="${_n(left)}" y="${_n(top)}" width="${_n(cw)}" '
            'height="${_n(ErdLayout.headerHeight)}" '
            'fill="${headerFills[t.name] ?? colors.header}"/>')
        ..writeln('<text x="${_n(left + 10)}" y="${_n(top + 21)}" '
            'font-weight="bold">'
            '${_esc(_fit(t.name, inner - countWidth, _nameCharPx))}</text>')
        ..writeln('<text x="${_n(left + cw - 10)}" y="${_n(top + 21)}" '
            'text-anchor="end" font-size="10" fill="${colors.muted}">'
            '$count</text>');
      for (var i = 0; i < t.columns.length; i++) {
        final c = t.columns[i];
        final rowTop = top + ErdLayout.headerHeight + ErdLayout.rowHeight * i;
        final baseline = rowTop + 15;
        var x = left + 10;
        if (c.isPrimaryKey) {
          b.writeln(_pill(x, rowTop, 'PK', colors.primaryKey));
          x += _pillStep;
        }
        if (c.isForeignKey) {
          b.writeln(_pill(x, rowTop, 'FK', colors.foreignKey));
        }
        final nameX = left + 10 + slot;
        // Type, then the UQ / AI / DF markers as on screen (#1277).
        final type = [
          c.isNullable ? '${c.type}?' : c.type,
          ...c.badges,
        ].join(' ');
        final typeWidth = min(type.length * _typeCharPx, typeAvail);
        final nameAvail = inner - slot - typeWidth - 6;
        b
          ..writeln('<text x="${_n(nameX)}" y="${_n(baseline)}"'
              '${c.isPrimaryKey ? ' font-weight="bold"' : ''}>'
              '${_esc(_fit(c.name, nameAvail, _nameCharPx))}</text>')
          ..writeln('<text x="${_n(left + cw - 10)}" y="${_n(baseline)}" '
              'text-anchor="end" font-size="10" font-family="monospace" '
              'fill="${colors.muted}">'
              '${_esc(_fit(type, typeAvail, _typeCharPx))}</text>');
      }
      b.writeln('</g>');
    }
    b.writeln('</svg>');
    return b.toString();
  }
}
