import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/features/erd/erd_model.dart';

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

  /// Standalone SVG rendering of the diagram.
  static String toSvg(ErdSchema schema, ErdLayout layout) {
    final byName = {for (final t in schema.tables) t.name: t};
    final w = layout.size.width, h = layout.size.height;
    final b = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" '
          'viewBox="0 0 $w $h" font-family="sans-serif" font-size="12">')
      ..writeln('<rect width="100%" height="100%" fill="#ffffff"/>');
    for (final r in schema.relations) {
      final from = byName[r.fromTable], to = byName[r.toTable];
      if (from == null || to == null) continue;
      final fr = layout.rectOf(from), tr = layout.rectOf(to);
      final fromRight = fr.center.dx < tr.center.dx;
      final x1 = fromRight ? fr.right : fr.left;
      final x2 = fromRight ? tr.left : tr.right;
      final y1 = layout.columnY(from, r.fromColumn);
      final y2 = layout.columnY(to, r.toColumn);
      b.writeln('<line x1="$x1" y1="$y1" x2="$x2" y2="$y2" '
          'stroke="#64748b" stroke-width="1.5"/>');
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
