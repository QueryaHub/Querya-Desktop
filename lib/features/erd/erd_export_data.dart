import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Turns what the diagram shows on screen (header tints, notes, group frames,
/// theme colours) into the plain values the SVG / DBML export takes (#1362).
///
/// Everything is a function of its arguments: the view state passes its data
/// and the theme lookups in, nothing here reads widget state.
abstract final class ErdExportData {
  static material.Color _fromHex(String hex) =>
      material.Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

  /// Header bands for the SVG: the screen's tint over the export's card colour.
  static Map<String, String> headerFills(
    ErdSchema schema,
    String cardHex, {
    required Map<String, String> headerColors,
    required material.Color Function(String table) headerColor,
  }) {
    final card = _fromHex(cardHex);
    return {
      for (final t in schema.tables)
        if (erdHeaderSlot(t.name, headerColors) != null)
          t.name: ErdSvgColors.hex(material.Color.alphaBlend(
                  headerColor(t.name).withValues(alpha: 0.14), card)
              .toARGB32()),
    };
  }

  /// Notes for the SVG, tinted as on screen over the export background.
  static List<ErdSvgNote> notes(
    List<ErdNote> notes,
    ErdSvgColors colors, {
    required material.Color Function(String slot) slotColor,
    required double noteTint,
  }) {
    final background = _fromHex(colors.background);
    final muted = _fromHex(colors.muted);
    return [
      for (final n in notes)
        ErdSvgNote(
          text: n.text,
          rect: material.Rect.fromLTWH(n.x, n.y, n.width, n.height),
          fill: ErdSvgColors.hex(material.Color.alphaBlend(
                  (n.color == null ? muted : slotColor(n.color!))
                      .withValues(alpha: n.color == null ? noteTint : 0.18),
                  background)
              .toARGB32()),
          stroke: n.color == null
              ? colors.border
              : ErdSvgColors.hex(slotColor(n.color!).toARGB32()),
        ),
    ];
  }

  /// Group frames for the SVG: the screen's tint over the export background.
  static List<ErdSvgGroup> groups(
    List<ErdGroup> groups,
    ErdLayout layout,
    String backgroundHex, {
    required material.Color Function(String slot) slotColor,
  }) {
    final background = _fromHex(backgroundHex);
    return [
      for (final g in groups)
        if (layout.frameOf(g.tables) case final frame?)
          ErdSvgGroup(
            name: g.name,
            frame: frame,
            fill: ErdSvgColors.hex(material.Color.alphaBlend(
                    slotColor(g.color).withValues(alpha: 0.06), background)
                .toARGB32()),
            stroke: ErdSvgColors.hex(slotColor(g.color).toARGB32()),
          ),
    ];
  }

  /// Colours of the current theme for the SVG export, as the screen draws the
  /// cards and edges.
  static ErdSvgColors themeColors(material.BuildContext context) {
    final wb = context.workbench;
    final palette = context.semanticPalette;
    String hex(material.Color c) => ErdSvgColors.hex(c.toARGB32());
    return ErdSvgColors(
      background: hex(wb.surface),
      card: hex(wb.surface),
      border: hex(wb.borderSubtle),
      header: hex(material.Color.alphaBlend(
          wb.accent.withValues(alpha: 0.10), wb.surface)),
      text: hex(shadcn.Theme.of(context).colorScheme.foreground),
      muted: hex(wb.mutedForeground),
      edge: hex(wb.mutedForeground),
      primaryKey: hex(palette.type1),
      foreignKey: hex(palette.type2),
    );
  }
}
