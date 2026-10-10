import 'dart:math' show max, min;
import 'dart:ui' show Offset, Rect, Size;

import 'package:querya_desktop/core/erd/erd_note_text.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart'
    show ErdGroup, ErdNote;
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

/// A group's frame in the SVG (#1282): its bounds from [ErdLayout.frameOf],
/// the tinted fill and the outline and title colour, as `#rrggbb`.
class ErdSvgGroup {
  const ErdSvgGroup({
    required this.name,
    required this.frame,
    required this.fill,
    required this.stroke,
  });

  final String name;
  final Rect frame;
  final String fill;
  final String stroke;
}

/// A sticky note in the SVG (#1283): its rectangle, text and colours.
class ErdSvgNote {
  const ErdSvgNote({
    required this.text,
    required this.rect,
    required this.fill,
    required this.stroke,
  });

  final String text;
  final Rect rect;
  final String fill;
  final String stroke;
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

  /// Glyph width of a note's 11 px text.
  static const double _noteCharPx = 6.2;

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

  // --- DBML (#1285) ---

  static final _dbmlPlainType = RegExp(
      r'^[A-Za-z_][A-Za-z0-9_]*(\(\s*\d+(\s*,\s*\d+)*\s*\))?(\[\])?$');
  static final _dbmlNumber = RegExp(r'^-?\d+(\.\d+)?$');
  // 'text' with an optional ::cast after it.
  static final _dbmlQuoted = RegExp(r"^'((?:[^']|'')*)'(?:::[^']*)?$");

  static String _q(String name) => '"${name.replaceAll('"', r'\"')}"';

  /// `"schema"."table"` for `schema.table`, else `"table"`.
  static String _dbmlTable(String name) {
    final dot = name.indexOf('.');
    if (dot <= 0 || dot == name.length - 1) return _q(name);
    return '${_q(name.substring(0, dot))}.${_q(name.substring(dot + 1))}';
  }

  /// A DBML string literal; one with a line break is a `'''` block.
  static String _dbmlString(String s) {
    final text = s.replaceAll(r'\', r'\\');
    if (text.contains('\n')) {
      return "'''\n${text.replaceAll("'''", r"\'''")}\n'''";
    }
    return "'${text.replaceAll("'", r"\'")}'";
  }

  /// A column's type: bare when DBML reads it as one word (`varchar(255)`),
  /// quoted otherwise (`"timestamp with time zone"`).
  static String _dbmlType(String type) {
    final t = type.trim();
    if (t.isEmpty) return '"unknown"';
    return _dbmlPlainType.hasMatch(t) ? t : _q(t);
  }

  /// A default as DBML writes it: a number, a boolean or null as is, a string
  /// literal as a string (its `::cast` dropped), anything else as an
  /// expression in backticks.
  static String _dbmlDefault(String value) {
    final v = value.trim();
    final lower = v.toLowerCase();
    if (_dbmlNumber.hasMatch(v) ||
        lower == 'true' ||
        lower == 'false' ||
        lower == 'null') {
      return lower == 'null' || lower == 'true' || lower == 'false'
          ? lower
          : v;
    }
    final m = _dbmlQuoted.firstMatch(v);
    if (m != null) {
      return "'${m.group(1)!.replaceAll("''", r"\'")}'";
    }
    return '`${v.replaceAll('`', "'")}`';
  }

  /// The DBML of [schema] (the shown tables), for dbdiagram and dbdocs:
  /// tables with `pk`, `unique`, `not null`, `default`, `increment` and
  /// notes, enums, refs, table groups and sticky notes. [headerColors] are
  /// `#rrggbb` per table.
  ///
  /// A foreign key on its own unique column is `-` (one-to-one), any other
  /// `>` (many-to-one). Composite primary keys go in an `indexes` block.
  static String toDbml(
    ErdSchema schema, {
    List<ErdGroup> groups = const [],
    List<ErdNote> notes = const [],
    Map<String, String> headerColors = const {},
  }) {
    final names = {for (final t in schema.tables) t.name};
    final b = StringBuffer('// Exported from Querya\n');

    // Enums by the name of their type; a type that is no plain word (MySQL's
    // enum('a','b')) is named after its column.
    final enums = <String, List<String>>{};
    final enumOf = <String, String>{};
    for (final t in schema.tables) {
      for (final c in t.columns) {
        if (c.enumValues.isEmpty) continue;
        final type = c.type.trim();
        final name = _dbmlPlainType.hasMatch(type) && !type.contains('(')
            ? type
            : '${t.name.replaceAll('.', '_')}_${c.name}';
        enums.putIfAbsent(name, () => c.enumValues);
        enumOf['${t.name}\u0000${c.name}'] = name;
      }
    }
    for (final e in enums.entries) {
      b.writeln('\nEnum ${_dbmlTable(e.key)} {');
      for (final v in e.value) {
        b.writeln('  ${_q(v)}');
      }
      b.writeln('}');
    }

    for (final t in schema.tables) {
      final settings = [
        if (headerColors[t.name] case final c?) 'headercolor: $c',
        if (t.comment case final note?) 'note: ${_dbmlString(note)}',
      ];
      b.writeln('\nTable ${_dbmlTable(t.name)}'
          '${settings.isEmpty ? '' : ' [${settings.join(', ')}]'} {');
      final pks = [for (final c in t.columns) if (c.isPrimaryKey) c];
      for (final c in t.columns) {
        final type = enumOf['${t.name}\u0000${c.name}'] != null
            ? _dbmlTable(enumOf['${t.name}\u0000${c.name}']!)
            : _dbmlType(c.type);
        final attrs = [
          if (c.isPrimaryKey && pks.length == 1) 'pk',
          if (c.isIdentity) 'increment',
          // Spelled out for the columns of a composite key too, which carry
          // no `pk` of their own.
          if (!c.isNullable && !(c.isPrimaryKey && pks.length == 1))
            'not null',
          if (c.isUnique && !c.isPrimaryKey) 'unique',
          if (c.defaultValue != null && !c.isIdentity)
            'default: ${_dbmlDefault(c.defaultValue!)}',
          if (c.comment case final note?) 'note: ${_dbmlString(note)}',
        ];
        b.writeln('  ${_q(c.name)} $type'
            '${attrs.isEmpty ? '' : ' [${attrs.join(', ')}]'}');
      }
      if (pks.length > 1) {
        b
          ..writeln('')
          ..writeln('  indexes {')
          ..writeln('    (${pks.map((c) => _q(c.name)).join(', ')}) [pk]')
          ..writeln('  }');
      }
      b.writeln('}');
    }

    var anyRef = false;
    for (final r in schema.relations) {
      if (!names.contains(r.fromTable) || !names.contains(r.toTable)) continue;
      if (!anyRef) b.writeln('');
      anyRef = true;
      b.writeln('Ref: ${_dbmlTable(r.fromTable)}.${_q(r.fromColumn)} '
          '${r.oneToOne ? '-' : '>'} '
          '${_dbmlTable(r.toTable)}.${_q(r.toColumn)}');
    }

    for (final g in groups) {
      final members = [for (final t in g.tables) if (names.contains(t)) t];
      if (members.isEmpty) continue;
      final settings = [
        if (g.note case final note?) 'note: ${_dbmlString(note)}',
      ];
      b.writeln('\nTableGroup ${_q(g.name)}'
          '${settings.isEmpty ? '' : ' [${settings.join(', ')}]'} {');
      for (final t in members) {
        b.writeln('  ${_dbmlTable(t)}');
      }
      b.writeln('}');
    }

    for (final n in notes) {
      b.writeln('\nNote ${_q('note_${n.id}')} {\n  ${_dbmlString(n.text)}\n}');
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
    List<ErdSvgGroup> groups = const [],
    List<ErdSvgNote> notes = const [],
  }) {
    var size = layout.size;
    for (final n in notes) {
      size = Size(max(size.width, n.rect.right + ErdLayout.margin),
          max(size.height, n.rect.bottom + ErdLayout.margin));
    }
    final w = _n(size.width), h = _n(size.height);
    final b = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" '
          'viewBox="0 0 $w $h" font-family="sans-serif" font-size="12" '
          'fill="${colors.text}">')
      ..writeln('<rect width="100%" height="100%" fill="${colors.background}"/>');
    // Group frames under the edges and cards, as on screen.
    for (final g in groups) {
      final f = g.frame;
      b
        ..writeln('<rect class="erd-group" x="${_n(f.left)}" y="${_n(f.top)}" '
            'width="${_n(f.width)}" height="${_n(f.height)}" rx="12" '
            'fill="${g.fill}" stroke="${g.stroke}" stroke-width="1.2"/>')
        ..writeln('<text class="erd-group-title" x="${_n(f.left + 12)}" '
            'y="${_n(f.top + 16)}" font-size="12" font-weight="bold" '
            'fill="${g.stroke}">'
            '${_esc(_fit(g.name, f.width - 24, _nameCharPx))}</text>');
    }
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
    // Sticky notes above the cards, text wrapped to the note's width.
    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final r = note.rect;
      final avail = r.width - 16;
      b
        ..writeln('<clipPath id="note$i"><rect x="${_n(r.left)}" '
            'y="${_n(r.top)}" width="${_n(r.width)}" height="${_n(r.height)}"/>'
            '</clipPath>')
        ..writeln('<rect class="erd-note" x="${_n(r.left)}" y="${_n(r.top)}" '
            'width="${_n(r.width)}" height="${_n(r.height)}" rx="6" '
            'fill="${note.fill}" stroke="${note.stroke}"/>')
        ..writeln('<g clip-path="url(#note$i)" font-size="11">');
      var y = r.top + 8 + 11;
      for (final line in parseErdNote(note.text)) {
        final prefix = line.bullet ? '•  ' : '';
        final plain = '$prefix${line.plain}';
        if (plain.length * _noteCharPx <= avail) {
          final runs = StringBuffer();
          for (final run in line.runs) {
            runs.write(run.bold
                ? '<tspan font-weight="bold">${_esc(run.text)}</tspan>'
                : _esc(run.text));
          }
          b.writeln('<text class="erd-note-line" x="${_n(r.left + 8)}" '
              'y="${_n(y)}" xml:space="preserve">${_esc(prefix)}$runs</text>');
          y += 15;
          continue;
        }
        // Too long for one line: wrapped by words, without the bold.
        var current = prefix;
        void flush() {
          b.writeln('<text class="erd-note-line" x="${_n(r.left + 8)}" '
              'y="${_n(y)}" xml:space="preserve">${_esc(current)}</text>');
          y += 15;
          current = '';
        }

        for (final word in line.plain.split(' ')) {
          final next = current.isEmpty || current == prefix
              ? '$current$word'
              : '$current $word';
          if (next.length * _noteCharPx > avail && current.trim().isNotEmpty) {
            flush();
            current = word;
          } else {
            current = next;
          }
        }
        if (current.isNotEmpty) flush();
      }
      b.writeln('</g>');
    }
    b.writeln('</svg>');
    return b.toString();
  }
}
