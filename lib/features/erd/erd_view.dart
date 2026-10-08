import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/features/erd/erd_model.dart';
import 'package:querya_desktop/features/erd/erd_router.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:querya_desktop/shared/widgets/querya_action_button.dart';
import 'package:querya_desktop/shared/widgets/querya_spinner.dart';
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
  List<ErdRoute> _routes = const [];
  String? _error;
  bool _loading = true;

  /// Table under the mouse, and the one being dragged: their edges are
  /// highlighted.
  String? _hovered;
  String? _dragging;

  final _transform = material.TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

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
        _setLayout(ErdLayout.compute(schema));
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

  void _setLayout(ErdLayout layout) {
    _layout = layout;
    final schema = _schema;
    _routes = schema == null ? const [] : ErdRouter.route(schema, layout);
  }

  void _autoLayout() {
    final schema = _schema;
    if (schema == null) return;
    setState(() => _setLayout(ErdLayout.compute(schema)));
  }

  void _dragStart(String table) => setState(() => _dragging = table);

  /// [screenDelta] is in screen pixels; the canvas may be zoomed.
  void _dragMove(String table, material.Offset screenDelta) {
    final layout = _layout;
    if (_dragging != table || layout == null) return;
    final scale = _transform.value.getMaxScaleOnAxis();
    final delta = screenDelta / (scale == 0 ? 1 : scale);
    setState(() =>
        _setLayout(layout.withPosition(table, layout.positions[table]! + delta)));
  }

  void _dragEnd() {
    if (_dragging == null) return;
    setState(() => _dragging = null);
  }

  Future<void> _save(String name, Uint8List bytes) =>
      (widget.onSaveFile ?? defaultErdFileSaver)(name, bytes);

  /// The focused table and the tables it is related to.
  bool _isFocused(ErdSchema schema, String table) {
    final focus = _dragging ?? _hovered;
    if (focus == null) return false;
    if (focus == table) return true;
    return schema.relations.any((r) =>
        (r.fromTable == focus && r.toTable == table) ||
        (r.toTable == focus && r.fromTable == table));
  }

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
      body = const material.Center(child: QueryaSpinner());
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
        transformationController: _transform,
        // A card drag must not pan the canvas.
        panEnabled: _dragging == null,
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
                      routes: _routes,
                      color: wb.mutedForeground,
                      highlight: wb.accent,
                      focus: _dragging ?? _hovered,
                    ),
                  ),
                ),
                for (final t in schema.tables)
                  material.Positioned(
                    left: layout.positions[t.name]!.dx,
                    top: layout.positions[t.name]!.dy,
                    child: _TableCard(
                      table: t,
                      highlighted: _isFocused(schema, t.name),
                      dragging: _dragging == t.name,
                      onOpen: widget.onOpenTable == null
                          ? null
                          : () => widget.onOpenTable!(t.name),
                      onHover: (inside) => setState(
                          () => _hovered = inside ? t.name : (_hovered == t.name ? null : _hovered)),
                      onDragStart: () => _dragStart(t.name),
                      onDragMove: (d) => _dragMove(t.name, d),
                      onDragEnd: _dragEnd,
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
          child: material.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              QueryaActionButton(
                key: const material.ValueKey('erd_refresh'),
                label: 'Refresh',
                icon: material.Icons.refresh_rounded,
                onPressed: _loading ? null : _load,
              ),
              QueryaActionButton(
                key: const material.ValueKey('erd_auto_layout'),
                label: 'Auto layout',
                icon: material.Icons.auto_fix_high_rounded,
                tooltip: 'Arrange the tables again (undoes manual moves)',
                onPressed: ready ? _autoLayout : null,
              ),
              QueryaActionButton(
                key: const material.ValueKey('erd_mermaid'),
                label: 'Mermaid',
                onPressed: !ready
                    ? null
                    : () => _save(
                          'diagram.mmd',
                          Uint8List.fromList(
                              utf8.encode(ErdExport.toMermaid(schema))),
                        ),
              ),
              QueryaActionButton(
                key: const material.ValueKey('erd_svg'),
                label: 'SVG',
                onPressed: !ready
                    ? null
                    : () => _save(
                          'diagram.svg',
                          Uint8List.fromList(utf8.encode(
                              ErdExport.toSvg(schema, layout, routes: _routes))),
                        ),
              ),
              QueryaActionButton(
                key: const material.ValueKey('erd_png'),
                label: 'PNG',
                onPressed: ready ? _exportPng : null,
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
  const _TableCard({
    required this.table,
    required this.highlighted,
    required this.dragging,
    required this.onHover,
    required this.onDragStart,
    required this.onDragMove,
    required this.onDragEnd,
    this.onOpen,
  });

  final ErdTable table;
  final bool highlighted;
  final bool dragging;
  final material.VoidCallback? onOpen;
  final void Function(bool inside) onHover;
  final material.VoidCallback onDragStart;
  final void Function(material.Offset delta) onDragMove;
  final material.VoidCallback onDragEnd;

  @override
  material.Widget build(material.BuildContext context) {
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
          onDoubleTap: onOpen,
          onPanStart: (_) => onDragStart(),
          onPanUpdate: (d) => onDragMove(d.delta),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          child: material.Container(
            width: ErdLayout.cardWidth,
            height: ErdLayout.cardHeight(table),
            decoration: material.BoxDecoration(
              color: wb.surface,
              borderRadius: radius,
              border: material.Border.all(
                color: highlighted ? wb.accent : wb.borderSubtle,
                width: highlighted ? 1.5 : 1,
              ),
              boxShadow: [
                material.BoxShadow(
                  color: const material.Color(0xFF000000)
                      .withValues(alpha: dragging ? 0.28 : 0.12),
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
                    color: wb.accent.withValues(alpha: highlighted ? 0.18 : 0.10),
                    padding: const material.EdgeInsets.symmetric(horizontal: 10),
                    child: material.Row(
                      children: [
                        material.Icon(material.Icons.table_chart_outlined,
                            size: 14, color: wb.accent),
                        const material.SizedBox(width: 6),
                        material.Expanded(
                          child: Text(table.name,
                              maxLines: 1,
                              overflow: material.TextOverflow.ellipsis,
                              style: const material.TextStyle(
                                  fontWeight: material.FontWeight.w600,
                                  fontSize: 13)),
                        ),
                        Text('${table.columns.length}',
                            style: material.TextStyle(
                                fontSize: 10, color: wb.mutedForeground)),
                      ],
                    ),
                  ),
                  for (final c in table.columns)
                    material.SizedBox(
                      height: ErdLayout.rowHeight,
                      child: material.Padding(
                        padding:
                            const material.EdgeInsets.symmetric(horizontal: 10),
                        child: material.Row(
                          children: [
                            material.SizedBox(
                              width: 20,
                              child: c.isPrimaryKey
                                  ? material.Icon(material.Icons.key_rounded,
                                      size: 12, color: palette.type1)
                                  : c.isForeignKey
                                      ? material.Icon(material.Icons.link_rounded,
                                          size: 12, color: palette.type2)
                                      : null,
                            ),
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
                            const material.SizedBox(width: 6),
                            Text(c.type,
                                maxLines: 1,
                                style: material.TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: wb.mutedForeground)),
                          ],
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

class _RelationPainter extends material.CustomPainter {
  _RelationPainter({
    required this.routes,
    required this.color,
    required this.highlight,
    required this.focus,
  });

  final List<ErdRoute> routes;
  final material.Color color;
  final material.Color highlight;

  /// Table whose relations are drawn on top in [highlight].
  final String? focus;

  bool _focused(ErdRoute r) =>
      focus != null &&
      (r.relation.fromTable == focus || r.relation.toTable == focus);

  @override
  void paint(material.Canvas canvas, material.Size size) {
    // Others first, focused on top.
    for (final pass in [false, true]) {
      for (final r in routes) {
        if (_focused(r) != pass || r.points.length < 2) continue;
        final paint = material.Paint()
          ..color = pass ? highlight : color.withValues(alpha: focus == null ? 0.85 : 0.35)
          ..style = material.PaintingStyle.stroke
          ..strokeWidth = pass ? 2 : 1.4
          ..strokeCap = material.StrokeCap.round
          ..strokeJoin = material.StrokeJoin.round;
        canvas.drawPath(roundedPath(r.points), paint);
        _crowFoot(canvas, r.points[0], r.points[1], paint);
        _oneBar(canvas, r.points.last, r.points[r.points.length - 2], paint);
      }
    }
  }

  /// "Many" end at the FK card: three prongs meeting 12 px out.
  static void _crowFoot(
      material.Canvas c, material.Offset edge, material.Offset next, material.Paint p) {
    final d = _dir(edge, next);
    final n = material.Offset(-d.dy, d.dx);
    final tip = edge + d * 12;
    c
      ..drawLine(tip, edge + n * 6, p)
      ..drawLine(tip, edge - n * 6, p)
      ..drawLine(tip, edge, p);
  }

  /// "One" end at the referenced card: a bar across the line.
  static void _oneBar(
      material.Canvas c, material.Offset edge, material.Offset prev, material.Paint p) {
    final d = _dir(edge, prev);
    final n = material.Offset(-d.dy, d.dx);
    final at = edge + d * 8;
    c.drawLine(at + n * 6, at - n * 6, p);
  }

  static material.Offset _dir(material.Offset from, material.Offset to) {
    final v = to - from;
    final len = v.distance;
    return len == 0 ? const material.Offset(1, 0) : v / len;
  }

  @override
  bool shouldRepaint(_RelationPainter old) =>
      old.routes != routes ||
      old.color != color ||
      old.highlight != highlight ||
      old.focus != focus;
}

/// Polyline with corners rounded by up to 8 px.
material.Path roundedPath(List<material.Offset> pts, {double radius = 8}) {
  final path = material.Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length - 1; i++) {
    final a = pts[i - 1], b = pts[i], c = pts[i + 1];
    final r = [radius, (b - a).distance / 2, (c - b).distance / 2]
        .reduce((x, y) => x < y ? x : y);
    final inDir = (b - a) / ((b - a).distance == 0 ? 1 : (b - a).distance);
    final outDir = (c - b) / ((c - b).distance == 0 ? 1 : (c - b).distance);
    final p1 = b - inDir * r, p2 = b + outDir * r;
    path
      ..lineTo(p1.dx, p1.dy)
      ..quadraticBezierTo(b.dx, b.dy, p2.dx, p2.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}
