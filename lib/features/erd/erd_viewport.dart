import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';

/// Where the canvas is: zoom and pan of the diagram in its viewport (#1690).
///
/// Wraps the [TransformationController] the `InteractiveViewer` drives and
/// the maths on it (zoom about a point, fit, centre on a point), so the view
/// asks for what it wants and not for matrices.
class ErdViewport {
  ErdViewport();

  static const double minScale = 0.2;
  static const double maxScale = 3;
  static const double zoomStep = 1.25;

  final transform = TransformationController();

  /// Marks the viewport box, to read its size once it has been laid out.
  final key = GlobalKey();

  /// Lowest zoom: [minScale], or lower when the whole diagram needs it to fit
  /// the viewport (a schema of a few hundred tables).
  double zoomFloor = minScale;

  double get scale => transform.value.getMaxScaleOnAxis();

  /// Where the canvas origin sits in the viewport.
  Offset get translation {
    final t = transform.value.getTranslation();
    return Offset(t.x, t.y);
  }

  /// Size of the viewport, once it has been laid out.
  Size? get size {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.size : null;
  }

  void dispose() => transform.dispose();

  /// Zoom [scale], with the canvas origin at [translation].
  void set({required double scale, required Offset translation}) {
    transform.value = Matrix4.identity()
      ..translate(translation.dx, translation.dy)
      ..scale(scale);
  }

  /// Sets the zoom to [target] (within the floor and [maxScale]), keeping the
  /// scene point under [focal] still.
  void zoomTo(double target, Offset focal) {
    final s = target.clamp(zoomFloor, maxScale).toDouble();
    final next = focal - (focal - translation) * (s / scale);
    set(scale: s, translation: next);
  }

  /// Zooms by [factor] about the middle of the viewport.
  void zoomBy(double factor) {
    final vs = size;
    if (vs == null) return;
    zoomTo(scale * factor, vs.center(Offset.zero));
  }

  /// Fits [content] into the viewport, centred, never enlarged. Returns
  /// whether [zoomFloor] changed (the viewer's lower limit moves with it), or
  /// null when the viewport is not laid out yet.
  bool? fit(Size content) {
    final vs = size;
    if (vs == null) return null;
    final s = ErdLayout.fitScale(content, vs);
    final floor = min(minScale, s);
    final changed = floor != zoomFloor;
    zoomFloor = floor;
    set(
      scale: s,
      translation: Offset(
        (vs.width - content.width * s) / 2,
        (vs.height - content.height * s) / 2,
      ),
    );
    return changed;
  }

  /// Centres the canvas point [point] in the viewport, keeping the zoom.
  void centreOn(Offset point) {
    final vs = size;
    if (vs == null) return;
    final s = scale;
    set(scale: s, translation: vs.center(Offset.zero) - point * s);
  }

  /// Canvas point at the middle of what the viewport shows, or [fallback]
  /// before the viewport is laid out.
  Offset centre({Offset fallback = const Offset(60, 60)}) {
    final vs = size;
    if (vs == null) return fallback;
    return MatrixUtils.transformPoint(
        Matrix4.inverted(transform.value), vs.center(Offset.zero));
  }

  /// A screen position as a canvas position.
  Offset toCanvas(Offset screen) =>
      MatrixUtils.transformPoint(Matrix4.inverted(transform.value), screen);

  /// A canvas position as a screen position.
  Offset toScreen(Offset canvas) =>
      MatrixUtils.transformPoint(transform.value, canvas);
}
