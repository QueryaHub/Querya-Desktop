import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_router.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/erd/erd_canvas_controls.dart';
import 'package:querya_desktop/features/erd/erd_viewport.dart';
import 'package:querya_desktop/features/erd/widgets/erd_relation_painter.dart';

/// The diagram's canvas: a zoomable, pannable sheet with the group frames,
/// the edges, the cards and the notes on it, and over it, in screen space, the
/// edge label, the search panel and the zoom controls (#1690).
///
/// The layers are built by the view and handed in; this puts them in order and
/// wires the viewport, the pointer and the keyboard to them.
class ErdCanvas extends material.StatelessWidget {
  const ErdCanvas({
    super.key,
    required this.viewport,
    required this.boundaryKey,
    required this.canvasFocus,
    required this.bindings,
    required this.canvasSize,
    required this.panEnabled,
    required this.routes,
    required this.focus,
    required this.pickedRelation,
    required this.edgeTip,
    required this.edgeTipLabel,
    required this.onTapUp,
    required this.onHover,
    required this.onLeave,
    required this.groupFrames,
    required this.cards,
    required this.notes,
    required this.searchPanel,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final ErdViewport viewport;

  /// The `RepaintBoundary` the PNG export captures.
  final material.GlobalKey boundaryKey;
  final material.FocusNode canvasFocus;
  final Map<material.ShortcutActivator, material.VoidCallback> bindings;
  final material.Size canvasSize;

  /// False while a card or a group is dragged: that drag must not pan.
  final bool panEnabled;
  final List<ErdRoute> routes;

  /// The table whose edges are highlighted.
  final ValueListenable<String?> focus;
  final ErdRelation? pickedRelation;

  /// The relation under the pointer and the pointer, in canvas space.
  final ValueListenable<(ErdRelation, material.Offset)?> edgeTip;
  final material.Widget Function(ErdRelation relation) edgeTipLabel;
  final void Function(material.Offset canvasPoint) onTapUp;
  final void Function(material.Offset canvasPoint) onHover;
  final material.VoidCallback onLeave;
  final List<material.Widget> groupFrames;
  final List<material.Widget> cards;
  final List<material.Widget> notes;
  final material.Widget searchPanel;
  final material.VoidCallback onZoomIn;
  final material.VoidCallback onZoomOut;
  final material.VoidCallback onFit;

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    return material.CallbackShortcuts(
      bindings: bindings,
      child: material.Focus(
        focusNode: canvasFocus,
        autofocus: true,
        child: material.Stack(
          key: viewport.key,
          children: [
            material.InteractiveViewer(
              constrained: false,
              transformationController: viewport.transform,
              panEnabled: panEnabled,
              minScale: viewport.zoomFloor,
              maxScale: ErdViewport.maxScale,
              boundaryMargin: const material.EdgeInsets.all(400),
              child: material.RepaintBoundary(
                key: boundaryKey,
                child: material.Container(
                  color: wb.surface,
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: material.GestureDetector(
                    // A tap on an edge picks its relation, elsewhere it clears
                    // the selection (#1281).
                    behavior: material.HitTestBehavior.translucent,
                    onTapUp: (d) => onTapUp(d.localPosition),
                    child: material.Stack(
                      children: [
                        // Lowest layer: sees the pointer wherever no card is,
                        // so edges can name themselves on hover.
                        material.Positioned.fill(
                          child: material.MouseRegion(
                            opaque: false,
                            onHover: (e) => onHover(e.localPosition),
                            onExit: (_) => onLeave(),
                            child: const material.SizedBox.expand(),
                          ),
                        ),
                        // Group frames under the edges and cards (#1282).
                        ...groupFrames,
                        material.Positioned.fill(
                          child: material.ValueListenableBuilder<String?>(
                            valueListenable: focus,
                            builder: (context, focus, _) =>
                                material.CustomPaint(
                              painter: ErdRelationPainter(
                                routes: routes,
                                color: wb.mutedForeground,
                                highlight: wb.accent,
                                focus: focus,
                                picked: pickedRelation,
                              ),
                            ),
                          ),
                        ),
                        ...cards,
                        // Sticky notes above the cards (#1283).
                        ...notes,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The edge label sits above the zoomed canvas, in screen space, so
            // it stays readable at any zoom and is never in a PNG.
            material.Positioned.fill(
              child: material.IgnorePointer(
                child: material.ListenableBuilder(
                  listenable:
                      material.Listenable.merge([edgeTip, viewport.transform]),
                  builder: (context, _) {
                    final tip = edgeTip.value;
                    if (tip == null) return const material.SizedBox.shrink();
                    final at = viewport.toScreen(tip.$2);
                    return material.Stack(
                      children: [
                        material.Positioned(
                          key: const material.ValueKey('erd_edge_tip'),
                          left: at.dx + 12,
                          top: at.dy + 12,
                          child: edgeTipLabel(tip.$1),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            material.Positioned(
              left: 8,
              top: 8,
              width: 260,
              child: searchPanel,
            ),
            material.Positioned(
              right: 8,
              bottom: 8,
              child: material.ValueListenableBuilder<material.Matrix4>(
                valueListenable: viewport.transform,
                builder: (context, m, _) => ErdZoomControls(
                  scale: m.getMaxScaleOnAxis(),
                  onZoomIn: onZoomIn,
                  onZoomOut: onZoomOut,
                  onFit: onFit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
