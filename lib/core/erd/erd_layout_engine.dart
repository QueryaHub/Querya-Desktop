import 'dart:math' show max, min;

import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';

/// The pure, widget-free part of the diagram's logic (#1362): what is visible,
/// how saved positions merge with a computed layout, which tables are related
/// and which match a search. No Flutter widgets, so it is unit-testable
/// without a widget tester.
abstract final class ErdLayoutEngine {
  /// The focused table as named in [schema]: `public.orders` falls back to
  /// `orders` when the current schema names it without a prefix.
  static String? focusIn(ErdSchema schema, String? focusTable) {
    final f = focusTable;
    if (f == null) return null;
    if (schema.tables.any((t) => t.name == f)) return f;
    final bare = f.contains('.') ? f.substring(f.indexOf('.') + 1) : f;
    return schema.tables.any((t) => t.name == bare) ? bare : null;
  }

  /// The schema as drawn: [hidden] tables gone, columns cut to keys in
  /// keys-only mode, and [collapsed] cards without columns.
  static ErdSchema visibleOf(
    ErdSchema schema, {
    required Set<String> hidden,
    required Set<String> collapsed,
    required ErdDetail detail,
  }) {
    final tables = [
      for (final t in schema.tables)
        if (!hidden.contains(t.name))
          ErdTable(
            name: t.name,
            comment: t.comment,
            columns: collapsed.contains(t.name) || detail == ErdDetail.names
                ? const []
                : [
                    for (final c in t.columns)
                      if (detail == ErdDetail.all ||
                          c.isPrimaryKey ||
                          c.isForeignKey)
                        c,
                  ],
          ),
    ];
    final names = {for (final t in tables) t.name};
    return ErdSchema(
      tables: tables,
      relations: [
        for (final r in schema.relations)
          if (names.contains(r.fromTable) && names.contains(r.toTable)) r,
      ],
    );
  }

  /// [computed] with the positions [saved] holds. Tables the saved layout
  /// does not know (new in the database) keep their computed arrangement,
  /// moved right of the saved cards so nothing overlaps.
  static ErdLayout withSaved(ErdLayout computed, ErdSavedLayout? saved) {
    if (saved == null || saved.positions.isEmpty) return computed;
    var layout = computed;
    var savedRight = 0.0;
    double? newLeft;
    for (final e in computed.positions.entries) {
      final p = saved.positions[e.key];
      if (p != null) {
        savedRight = max(savedRight, p.dx + computed.widthFor(e.key));
      } else {
        newLeft = newLeft == null ? e.value.dx : min(newLeft, e.value.dx);
      }
    }
    final shift =
        newLeft == null ? 0.0 : savedRight + ErdLayout.layerGap - newLeft;
    for (final e in computed.positions.entries) {
      final p = saved.positions[e.key];
      layout = layout.withPosition(e.key, p ?? e.value.translate(shift, 0));
    }
    return layout;
  }

  /// For a many-to-many link table: the tables it links, `users and roles`.
  static Map<String, String> junctionMap(ErdSchema schema) => {
        for (final t in schema.tables)
          if (t.isJunction)
            t.name: {
              for (final r in schema.relations)
                if (r.fromTable == t.name) r.toTable,
            }.join(' and '),
      };

  /// Tables related to each table by a foreign key, either way. Built once per
  /// build, so the focus test is a set lookup per card.
  static Map<String, Set<String>> neighbourMap(ErdSchema schema) {
    final out = <String, Set<String>>{};
    for (final r in schema.relations) {
      out.putIfAbsent(r.fromTable, () => {}).add(r.toTable);
      out.putIfAbsent(r.toTable, () => {}).add(r.fromTable);
    }
    return out;
  }

  /// Whether [table] is the focus or related to it.
  static bool isFocusedIn(
    Map<String, Set<String>> neighbours,
    String? focus,
    String table,
  ) {
    if (focus == null) return false;
    return focus == table || (neighbours[focus]?.contains(table) ?? false);
  }

  /// The tables whose name contains [query], at most [limit].
  static List<ErdTable> matches(
    ErdSchema schema,
    String query, {
    int limit = 8,
  }) {
    final q = query.toLowerCase();
    return [
      for (final t in schema.tables)
        if (t.name.toLowerCase().contains(q)) t,
    ].take(limit).toList();
  }
}
