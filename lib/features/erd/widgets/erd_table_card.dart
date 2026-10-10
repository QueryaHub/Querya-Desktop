import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// A card's share of the focus: highlighted, faded, and the column of a
/// picked relation on it, if any.
typedef ErdCardFocus = ({bool highlighted, bool faded, String? column});

/// Card builds so far. A test seam: hovering one card must not rebuild the
/// others.
@visibleForTesting
int erdCardBuilds = 0;

/// One table of the diagram: header, columns with their markers and badges.
class ErdTableCard extends material.StatelessWidget {
  const ErdTableCard({
    super.key,
    required this.table,
    required this.width,
    required this.headerColor,
    required this.highlighted,
    this.marked = false,
    this.focusColumn,
    this.junctionOf,
    required this.dragging,
    required this.onHover,
    required this.onDragStart,
    required this.onDragMove,
    required this.onDragEnd,
    this.onOpen,
    this.onSelect,
  });

  final ErdTable table;

  /// From the layout: sized to the card's content (#1276).
  final double width;

  /// Header tint and icon: by schema, picked per table, or the accent.
  final material.Color headerColor;
  final bool highlighted;

  /// Marked for a group with Shift / Ctrl + click (#1282).
  final bool marked;

  /// The column of a picked relation on this card, shaded (#1281).
  final String? focusColumn;

  /// For a many-to-many link table: the tables it links.
  final String? junctionOf;
  final bool dragging;
  final material.VoidCallback? onOpen;
  final material.VoidCallback? onSelect;
  final void Function(bool inside) onHover;
  final material.VoidCallback onDragStart;
  final void Function(material.Offset delta) onDragMove;
  final material.VoidCallback onDragEnd;

  /// Everything a row knows, one fact a line.
  static String _columnTip(ErdColumn c) => [
        '${c.name}  ${c.type}',
        if (c.isPrimaryKey) 'Primary key',
        if (c.isForeignKey) 'Foreign key',
        c.isNullable ? 'Nullable' : 'Not null',
        if (c.isUnique && !c.isPrimaryKey) 'Unique',
        if (c.isIdentity) 'Generated (identity / auto increment)',
        if (c.defaultValue case final d?) 'Default: $d',
        if (c.domainBase case final b?) 'Domain over $b',
        if (c.enumValues.isNotEmpty) 'Values: ${_enumList(c.enumValues)}',
        if (c.comment case final n?) 'Note: $n',
      ].join('\n');

  /// At most [cap] labels, then how many more.
  static String _enumList(List<String> values, {int cap = 12}) =>
      values.length <= cap
          ? values.join(', ')
          : '${values.take(cap).join(', ')} (+${values.length - cap} more)';

  /// Shadows read only on light surfaces, so a dark canvas gets twice the alpha.
  double _shadowAlpha(material.Color canvas) {
    final base = dragging ? 0.28 : 0.12;
    return canvas.computeLuminance() < 0.5 ? base * 2 : base;
  }

  @override
  material.Widget build(material.BuildContext context) {
    erdCardBuilds++;
    final wb = context.workbench;
    final palette = context.semanticPalette;
    final radius = material.BorderRadius.circular(8);
    return material.MouseRegion(
        cursor: dragging
            ? material.SystemMouseCursors.grabbing
            : material.SystemMouseCursors.grab,
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        // The card's pan recognizer joins the arena before the canvas's one
        // and wins it, so dragging a card never pans the canvas. `down`
        // reports the movement from the press, slop included.
        child: material.GestureDetector(
          key: material.ValueKey('erd_table_${table.name}'),
          dragStartBehavior: DragStartBehavior.down,
          onTap: onSelect,
          onDoubleTap: onOpen,
          onPanStart: (_) => onDragStart(),
          onPanUpdate: (d) => onDragMove(d.delta),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          child: material.Container(
            width: width,
            height: ErdLayout.cardHeight(table),
            decoration: material.BoxDecoration(
              color: wb.surface,
              borderRadius: radius,
              border: material.Border.all(
                color: highlighted || marked ? wb.accent : wb.borderSubtle,
                width: highlighted ? 1.5 : 1,
              ),
              boxShadow: [
                // A marked card gets a ring outside it, so its content area
                // is the one the card was measured for.
                if (marked)
                  material.BoxShadow(color: wb.accent, spreadRadius: 2.5),
                material.BoxShadow(
                  color: wb.shadow.withValues(alpha: _shadowAlpha(wb.canvas)),
                  blurRadius: dragging ? 18 : 8,
                  offset: material.Offset(0, dragging ? 6 : 2),
                ),
              ],
            ),
            child: material.ClipRRect(
              borderRadius: radius,
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  material.Container(
                    height: ErdLayout.headerHeight,
                    color: headerColor.withValues(
                        alpha: highlighted ? 0.18 : 0.10),
                    padding: const material.EdgeInsets.symmetric(horizontal: 10),
                    child: material.Row(
                      children: [
                        material.Icon(material.Icons.table_chart_outlined,
                            size: 14, color: headerColor),
                        const material.SizedBox(width: 6),
                        material.Expanded(
                          child: Text(table.name,
                              maxLines: 1,
                              overflow: material.TextOverflow.ellipsis,
                              style: const material.TextStyle(
                                  fontWeight: material.FontWeight.w600,
                                  fontSize: 13)),
                        ),
                        // The table's comment in the database (#1279).
                        if (table.comment case final note?) ...[
                          material.Tooltip(
                            message: note,
                            child: material.Icon(material.Icons.notes_rounded,
                                key: material.ValueKey(
                                    'erd_note_${table.name}'),
                                size: 13,
                                color: wb.mutedForeground),
                          ),
                          const material.SizedBox(width: 6),
                        ],
                        // A many-to-many link table (#1281).
                        if (junctionOf case final linked?) ...[
                          material.Tooltip(
                            message: 'Link table: many-to-many between $linked',
                            child: Text('M:N',
                                key: material.ValueKey(
                                    'erd_junction_${table.name}'),
                                style: material.TextStyle(
                                    fontSize: 9,
                                    fontWeight: material.FontWeight.w700,
                                    color: headerColor)),
                          ),
                          const material.SizedBox(width: 6),
                        ],
                        Text('${table.columns.length}',
                            style: material.TextStyle(
                                fontSize: 10, color: wb.mutedForeground)),
                      ],
                    ),
                  ),
                  for (final c in table.columns)
                    material.Container(
                      key: c.name == focusColumn
                          ? material.ValueKey(
                              'erd_focus_column_${table.name}_${c.name}')
                          : null,
                      height: ErdLayout.rowHeight,
                      // The column of a picked relation (#1281).
                      color: c.name == focusColumn
                          ? wb.accent.withValues(alpha: 0.14)
                          : null,
                      child: material.Tooltip(
                        message: _columnTip(c),
                        child: material.Padding(
                          padding: const material.EdgeInsets.symmetric(
                              horizontal: 10),
                          child: material.Row(
                            children: [
                              // A column can be both PK and FK (junction
                              // tables), so both markers get a slot.
                              material.SizedBox(
                                width: 26,
                                child: material.Row(
                                  mainAxisSize: material.MainAxisSize.min,
                                  children: [
                                    if (c.isPrimaryKey)
                                      material.Icon(material.Icons.key_rounded,
                                          size: 11, color: palette.type1),
                                    if (c.isPrimaryKey && c.isForeignKey)
                                      const material.SizedBox(width: 4),
                                    if (c.isForeignKey)
                                      material.Icon(material.Icons.link_rounded,
                                          size: 11, color: palette.type2),
                                  ],
                                ),
                              ),
                              // The card is measured to fit both; at its
                              // maximum width the name gives way.
                              material.Expanded(
                                child: Text(c.name,
                                    maxLines: 1,
                                    overflow: material.TextOverflow.ellipsis,
                                    style: material.TextStyle(
                                      fontSize: 12,
                                      fontWeight: c.isPrimaryKey
                                          ? material.FontWeight.w600
                                          : material.FontWeight.normal,
                                    )),
                              ),
                              const material.SizedBox(width: 8),
                              material.ConstrainedBox(
                                // Only a card at its maximum width has to
                                // share: then the type keeps half the row.
                                constraints: material.BoxConstraints(
                                    maxWidth: width >= ErdLayout.maxCardWidth
                                        ? (width - 56) / 2
                                        : double.infinity),
                                child: Text(c.isNullable ? '${c.type}?' : c.type,
                                    maxLines: 1,
                                    overflow: material.TextOverflow.ellipsis,
                                    style: material.TextStyle(
                                        fontSize: 10,
                                        fontFamily: QueryaTypography.mono,
                                        fontFamilyFallback:
                                            QueryaTypography.monoFontFamilyFallback,
                                        color: wb.mutedForeground)),
                              ),
                              if (c.comment != null) ...[
                                const material.SizedBox(width: 3),
                                material.Icon(material.Icons.notes_rounded,
                                    key: material.ValueKey(
                                        'erd_note_${table.name}_${c.name}'),
                                    size: 10,
                                    color: wb.mutedForeground),
                              ],
                              // UQ / AI / DF after the type (#1277).
                              for (final b in c.badges) ...[
                                const material.SizedBox(width: 3),
                                Text(b,
                                    key: material.ValueKey(
                                        'erd_badge_${table.name}_${c.name}_$b'),
                                    style: material.TextStyle(
                                        fontSize: 9,
                                        fontWeight: material.FontWeight.w700,
                                        color: switch (b) {
                                          'EN' => palette.type5,
                                          'UQ' => palette.type3,
                                          'AI' => palette.type4,
                                          _ => wb.mutedForeground,
                                        })),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ),
    );
  }
}
