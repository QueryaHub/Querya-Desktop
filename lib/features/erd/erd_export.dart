import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/features/erd/erd_model.dart';
import 'package:querya_desktop/features/erd/erd_router.dart';

/// Text exports of an [ErdSchema].
class ErdExport {
  ErdExport._();

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

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _n(double v) => v.toStringAsFixed(1);

  /// Standalone SVG rendering of the diagram, with the same positions and
  /// edge routes as the screen ([routes] defaults to a fresh routing).
  static String toSvg(ErdSchema schema, ErdLayout layout, {List<ErdRoute>? routes}) {
    final size = layout.size;
    final w = _n(size.width), h = _n(size.height);
    final b = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" '
          'viewBox="0 0 $w $h" font-family="sans-serif" font-size="12">')
      ..writeln('<rect width="100%" height="100%" fill="#ffffff"/>');
    for (final r in routes ?? ErdRouter.route(schema, layout)) {
      if (r.points.length < 2) continue;
      final d = StringBuffer('M ${_n(r.points.first.dx)} ${_n(r.points.first.dy)}');
      for (final p in r.points.skip(1)) {
        d.write(' L ${_n(p.dx)} ${_n(p.dy)}');
      }
      b.writeln('<path d="$d" fill="none" stroke="#64748b" stroke-width="1.5" '
          'stroke-linejoin="round"><title>${_esc(r.relation.fromTable)}.'
          '${_esc(r.relation.fromColumn)} → ${_esc(r.relation.toTable)}.'
          '${_esc(r.relation.toColumn)}</title></path>');
    }
    for (final t in schema.tables) {
      final rect = layout.rectOf(t);
      b
        ..writeln('<rect x="${rect.left}" y="${rect.top}" width="${rect.width}" '
            'height="${rect.height}" rx="6" fill="#f8fafc" stroke="#94a3b8"/>')
        ..writeln('<text x="${rect.left + 10}" y="${rect.top + 21}" '
            'font-weight="bold">${_esc(t.name)}</text>');
      for (var i = 0; i < t.columns.length; i++) {
        final c = t.columns[i];
        final y = rect.top + ErdLayout.headerHeight + ErdLayout.rowHeight * i + 15;
        final tag = [
          if (c.isPrimaryKey) 'PK',
          if (c.isForeignKey) 'FK',
        ].join(' ');
        b.writeln('<text x="${rect.left + 10}" y="$y">'
            '${tag.isEmpty ? '' : '[$tag] '}${_esc(c.name)} '
            '<tspan fill="#64748b">${_esc(c.type)}</tspan></text>');
      }
    }
    b.writeln('</svg>');
    return b.toString();
  }
}
