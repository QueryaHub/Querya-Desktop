import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_router.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/core/export/image_pdf.dart';
import 'package:querya_desktop/core/export/svg_png.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';
import 'package:querya_desktop/features/erd/widgets/erd_export_menu.dart';

/// What the exporter needs from the diagram view (#1362): its data, the
/// colours it draws with, and the canvas it captures.
abstract interface class ErdExportSource {
  /// For toasts; only used while [exportMounted].
  material.BuildContext get exportContext;
  bool get exportMounted;

  /// `<database>-erd`, or `erd` when the database name is unknown.
  String get fileStem;

  Future<void> saveFile(String name, Uint8List bytes);

  List<ErdRoute> get routes;
  List<ErdGroup> get groups;
  List<ErdNote> get notes;

  /// Header colour slot of each table the user (or the schema) tinted.
  Map<String, String> get headerColorSlots;
  material.Color slotColor(String slot);

  material.Size canvasSize(ErdLayout layout);

  /// Colours of the current theme for the SVG export.
  ErdSvgColors currentThemeColors();
  Map<String, String> headerFills(ErdSchema schema, String cardHex);
  List<ErdSvgGroup> svgGroups(ErdLayout layout, String backgroundHex);
  List<ErdSvgNote> svgNotes(ErdSvgColors colors);

  /// The repaint boundary of the canvas, or null when it is not built.
  RenderRepaintBoundary? get canvasBoundary;

  /// Runs [capture] with the screen-only state (the pick, a picked relation,
  /// the marks for a group, the hover) hidden, and puts it back after.
  Future<void> withCleanCanvas(Future<void> Function() capture);
}

/// The diagram's export flows: Mermaid, DBML, SVG, PNG and PDF, and the
/// setting that picks the light palette or the current theme.
class ErdExporter {
  ErdExporter(this._source);

  final ErdExportSource _source;

  void export(ErdExportAction action, ErdSchema schema, ErdLayout layout) {
    final stem = _source.fileStem;
    switch (action) {
      case ErdExportAction.mermaid:
        unawaited(_source.saveFile(
            '$stem.mmd', Uint8List.fromList(utf8.encode(ErdExport.toMermaid(schema)))));
      case ErdExportAction.svg:
        unawaited(_exportSvg(schema, layout));
      case ErdExportAction.png:
        unawaited(_exportPng(schema, layout));
      case ErdExportAction.pdfA4:
        unawaited(_exportPdf(schema, layout, PdfPaper.a4));
      case ErdExportAction.pdfA3:
        unawaited(_exportPdf(schema, layout, PdfPaper.a3));
      case ErdExportAction.dbml:
        unawaited(_source.saveFile(
            '$stem.dbml', Uint8List.fromList(utf8.encode(dbml(schema)))));
      case ErdExportAction.copyDbml:
        Clipboard.setData(ClipboardData(text: dbml(schema)));
        showAppToast(
          context: _source.exportContext,
          message: 'DBML copied to the clipboard',
        );
      case ErdExportAction.toggleTheme:
        unawaited(_toggleExportTheme());
      case ErdExportAction.copyMermaid:
        Clipboard.setData(ClipboardData(text: ErdExport.toMermaid(schema)));
        showAppToast(
          context: _source.exportContext,
          message: 'Mermaid copied to the clipboard',
        );
    }
  }

  /// The DBML of what the diagram shows: its groups and notes, and the
  /// header colours it draws.
  String dbml(ErdSchema schema) {
    final shown = {for (final t in schema.tables) t.name};
    return ErdExport.toDbml(
      schema,
      groups: [
        for (final g in _source.groups)
          if (g.tables.any(shown.contains)) g,
      ],
      notes: List.of(_source.notes),
      headerColors: {
        for (final t in schema.tables)
          if (erdHeaderSlot(t.name, _source.headerColorSlots) case final slot?)
            t.name: ErdSvgColors.hex(_source.slotColor(slot).toARGB32()),
      },
    );
  }

  Future<void> _exportPng(ErdSchema schema, ErdLayout layout) async {
    final currentTheme = await AppSettings.instance.getExportCurrentTheme();
    if (!_source.exportMounted) return;
    final stem = _source.fileStem;
    if (!currentTheme) {
      final scale = ErdExport.pngPixelRatio(_source.canvasSize(layout));
      const light = ErdSvgColors();
      final svg = ErdExport.toSvg(schema, layout,
          routes: _source.routes,
          headerFills: _source.headerFills(schema, light.card),
          groups: _source.svgGroups(layout, light.background),
          notes: _source.svgNotes(light));
      await _source.saveFile('$stem.png', await svgToPng(svg, scale: scale));
      return;
    }
    final boundary = _source.canvasBoundary;
    if (boundary == null) return;
    await _source.withCleanCanvas(() async {
      if (!_source.exportMounted) return;
      final context = _source.exportContext;
      try {
        final ratio = ErdExport.pngPixelRatio(boundary.size);
        if (ratio < 1) {
          showAppToast(
            context: context,
            message: 'The diagram is larger than '
                '${ErdExport.pngMaxSide} px per side, so the PNG is at '
                '${(ratio * 100).round()}% resolution. The SVG export keeps full detail.',
          );
        }
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data == null) throw StateError('no image data');
        await _source.saveFile('$stem.png', data.buffer.asUint8List());
      } catch (e) {
        final failed = _source.exportContext;
        if (failed.mounted) {
          showAppToast(
            context: failed,
            variant: AppToastVariant.error,
            message: 'Could not render the PNG ($e). '
                'Export SVG instead: it has no size limit.',
          );
        }
      }
    });
  }

  /// The diagram as SVG text, in the export palette: light for documents,
  /// unless the setting asks for the current theme.
  Future<String?> _svgText(ErdSchema schema, ErdLayout layout) async {
    final currentTheme = await AppSettings.instance.getExportCurrentTheme();
    if (!_source.exportMounted) return null;
    final colors =
        currentTheme ? _source.currentThemeColors() : const ErdSvgColors();
    return ErdExport.toSvg(schema, layout,
        routes: _source.routes,
        colors: colors,
        headerFills: _source.headerFills(schema, colors.card),
        groups: _source.svgGroups(layout, colors.background),
        notes: _source.svgNotes(colors));
  }

  Future<void> _exportSvg(ErdSchema schema, ErdLayout layout) async {
    final svg = await _svgText(schema, layout);
    if (svg == null) return;
    await _source.saveFile(
        '${_source.fileStem}.svg', Uint8List.fromList(utf8.encode(svg)));
  }

  /// The PDF export: the SVG fitted on one page of [paper].
  Future<void> _exportPdf(
      ErdSchema schema, ErdLayout layout, PdfPaper paper) async {
    final svg = await _svgText(schema, layout);
    if (svg == null) return;
    try {
      await _source.saveFile(
          '${_source.fileStem}.pdf', await svgToPdf(svg, paper: paper));
    } catch (e) {
      final failed = _source.exportContext;
      if (failed.mounted) {
        showAppToast(
          context: failed,
          variant: AppToastVariant.error,
          message: 'Could not render the PDF ($e). Export SVG instead.',
        );
      }
    }
  }

  /// Flips between the light export palette and the current theme.
  Future<void> _toggleExportTheme() async {
    final now = !await AppSettings.instance.getExportCurrentTheme();
    await AppSettings.instance.setExportCurrentTheme(now);
    final context = _source.exportContext;
    if (!context.mounted) return;
    showAppToast(
      context: context,
      message: now
          ? 'Exports use the current theme'
          : 'Exports use the light palette for documents',
    );
  }
}
