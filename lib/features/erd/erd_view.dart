import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/features/erd/erd_model.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Saves an exported diagram file; replaceable in tests.
typedef ErdFileSaver = Future<void> Function(String name, Uint8List bytes);

Future<void> defaultErdFileSaver(String name, Uint8List bytes) async {
  final ext = name.split('.').last;
  final location = await getSaveLocation(
    acceptedTypeGroups: [
      XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
    ],
    suggestedName: name,
  );
  if (location == null) return;
  await XFile.fromData(bytes, name: name).saveTo(location.path);
}

/// Interactive entity-relationship diagram of the connected database.
class ErdView extends material.StatefulWidget {
  const ErdView({
    super.key,
    required this.delegate,
    required this.dialect,
    this.onOpenTable,
    this.onSaveFile,
  });

  final SqlExecutionDelegate delegate;
  final SqlDialect dialect;

  /// Called on double tap of a table card.
  final void Function(String table)? onOpenTable;
  final ErdFileSaver? onSaveFile;

  @override
  material.State<ErdView> createState() => _ErdViewState();
}

class _ErdViewState extends material.State<ErdView> {
  final _boundaryKey = material.GlobalKey();
  ErdSchema? _schema;
  ErdLayout? _layout;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schema = await ErdCatalog.load(widget.delegate, widget.dialect);
      if (!mounted) return;
      setState(() {
        _schema = schema;
        _layout = ErdLayout.compute(schema);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save(String name, Uint8List bytes) =>
      (widget.onSaveFile ?? defaultErdFileSaver)(name, bytes);

  Future<void> _exportPng() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    await _save('diagram.png', data.buffer.asUint8List());
  }

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    final schema = _schema;
    final layout = _layout;
    material.Widget body;
    if (_loading) {
      body = const material.Center(child: material.CircularProgressIndicator());
    } else if (_error != null) {
      body = material.Center(child: Text(_error!));
    } else if (schema == null || layout == null || schema.isEmpty) {
      body = material.Center(
        child: Text('No tables found',
            style: material.TextStyle(color: wb.mutedForeground)),
      );
    } else {
      body = material.InteractiveViewer(
        constrained: false,
        minScale: 0.2,
        maxScale: 3,
        boundaryMargin: const material.EdgeInsets.all(400),
        child: material.RepaintBoundary(
          key: _boundaryKey,
          child: material.Container(
            color: wb.surface,
            width: layout.size.width,
            height: layout.size.height,
            child: material.Stack(
              children: [
                material.Positioned.fill(
                  child: material.CustomPaint(
                    painter: _RelationPainter(
                      schema: schema,
                      layout: layout,
                      color: wb.mutedForeground,
                    ),
                  ),
                ),
                for (final t in schema.tables)
                  material.Positioned(
                    left: layout.positions[t.name]!.dx,
                    top: layout.positions[t.name]!.dy,
                    child: _TableCard(
                      table: t,
                      onOpen: widget.onOpenTable == null
                          ? null
                          : () => widget.onOpenTable!(t.name),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final ready = schema != null && layout != null && !schema.isEmpty;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Padding(
          padding: const material.EdgeInsets.all(8),
          child: material.Row(
            children: [
              OutlineButton(
                key: const material.ValueKey('erd_refresh'),
                onPressed: _loading ? null : _load,
                child: const Text('Refresh'),
              ),
              const material.SizedBox(width: 8),
              OutlineButton(
                key: const material.ValueKey('erd_mermaid'),
                onPressed: !ready
                    ? null
                    : () => _save(
                          'diagram.mmd',
                          Uint8List.fromList(
                              utf8.encode(ErdExport.toMermaid(schema))),
                        ),
                child: const Text('Mermaid'),
              ),
              const material.SizedBox(width: 8),
              OutlineButton(
                key: const material.ValueKey('erd_svg'),
                onPressed: !ready
                    ? null
                    : () => _save(
                          'diagram.svg',
                          Uint8List.fromList(
                              utf8.encode(ErdExport.toSvg(schema, layout))),
                        ),
                child: const Text('SVG'),
              ),
              const material.SizedBox(width: 8),
              OutlineButton(
                key: const material.ValueKey('erd_png'),
                onPressed: ready ? _exportPng : null,
                child: const Text('PNG'),
              ),
            ],
          ),
        ),
        material.Expanded(child: material.ClipRect(child: body)),
      ],
    );
  }
}

class _TableCard extends material.StatelessWidget {
  const _TableCard({required this.table, this.onOpen});

  final ErdTable table;
  final material.VoidCallback? onOpen;

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    final palette = context.semanticPalette;
    return material.GestureDetector(
      key: material.ValueKey('erd_table_${table.name}'),
      onDoubleTap: onOpen,
      child: material.Container(
        width: ErdLayout.cardWidth,
        height: ErdLayout.cardHeight(table),
        decoration: material.BoxDecoration(
          color: wb.surface,
          border: material.Border.all(color: wb.borderSubtle),
          borderRadius: material.BorderRadius.circular(6),
        ),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            material.Container(
              height: ErdLayout.headerHeight,
              alignment: material.Alignment.centerLeft,
              padding: const material.EdgeInsets.symmetric(horizontal: 10),
              child: Text(table.name,
                  maxLines: 1,
                  overflow: material.TextOverflow.ellipsis,
                  style: const material.TextStyle(
                      fontWeight: material.FontWeight.bold)),
            ),
            for (final c in table.columns)
              material.SizedBox(
                height: ErdLayout.rowHeight,
                child: material.Padding(
                  padding: const material.EdgeInsets.symmetric(horizontal: 10),
                  child: material.Row(
                    children: [
                      material.SizedBox(
                        width: 26,
                        child: Text(
                          c.isPrimaryKey
                              ? 'PK'
                              : c.isForeignKey
                                  ? 'FK'
                                  : '',
                          style: material.TextStyle(
                            fontSize: 9,
                            color: c.isPrimaryKey
                                ? palette.type1
                                : palette.type2,
                          ),
                        ),
                      ),
                      material.Expanded(
                        child: Text(c.name,
                            maxLines: 1,
                            overflow: material.TextOverflow.ellipsis,
                            style: const material.TextStyle(fontSize: 12)),
                      ),
                      Text(c.type,
                          maxLines: 1,
                          style: material.TextStyle(
                              fontSize: 10, color: wb.mutedForeground)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RelationPainter extends material.CustomPainter {
  _RelationPainter({
    required this.schema,
    required this.layout,
    required this.color,
  });

  final ErdSchema schema;
  final ErdLayout layout;
  final material.Color color;

  @override
  void paint(material.Canvas canvas, material.Size size) {
    final paint = material.Paint()
      ..color = color
      ..style = material.PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final byName = {for (final t in schema.tables) t.name: t};
    for (final r in schema.relations) {
      final from = byName[r.fromTable], to = byName[r.toTable];
      if (from == null || to == null) continue;
      final fr = layout.rectOf(from), tr = layout.rectOf(to);
      final fromRight = fr.center.dx < tr.center.dx;
      final p1 = material.Offset(
          fromRight ? fr.right : fr.left, layout.columnY(from, r.fromColumn));
      final p2 = material.Offset(
          fromRight ? tr.left : tr.right, layout.columnY(to, r.toColumn));
      final dx = (fromRight ? 1 : -1) * 30.0;
      final path = material.Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(p1.dx + dx, p1.dy, p2.dx - dx, p2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);
      canvas.drawCircle(p2, 3, paint..style = material.PaintingStyle.fill);
      paint.style = material.PaintingStyle.stroke;
    }
  }

  @override
  bool shouldRepaint(_RelationPainter old) =>
      old.schema != schema || old.layout != layout || old.color != color;
}
