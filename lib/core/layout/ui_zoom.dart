import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The smallest layout the app is built for, in logical pixels: the minimum
/// window size. The interface scale never zooms the layout below it, so a big
/// scale in a small window is capped instead of overflowing.
const Size kMinUiLayoutSize = Size(900, 600);

/// The lowest zoom ever applied, whatever the window.
const double kLowestUiZoom = 0.5;

/// The zoom actually used for [requested] in a [window]: the requested scale,
/// but no higher than keeps [kMinUiLayoutSize] available to the layout.
double effectiveUiScale({required double requested, required Size window}) {
  final cap = math.min(
    window.width / kMinUiLayoutSize.width,
    window.height / kMinUiLayoutSize.height,
  );
  return math.min(requested, math.max(cap, kLowestUiZoom));
}

/// What [QueryaUiZoom] applied below it.
class QueryaUiZoomScope extends InheritedWidget {
  const QueryaUiZoomScope({
    super.key,
    required this.requested,
    required this.effective,
    required super.child,
  });

  /// The scale the user asked for (Preferences → Appearance).
  final double requested;

  /// The zoom in use this frame: lower than [requested] when the window is too
  /// small for it, and moving towards it while a change is animated.
  final double effective;

  static QueryaUiZoomScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<QueryaUiZoomScope>();

  /// True when the window is too small for the requested scale.
  bool get isCapped => effective < requested - 0.005;

  @override
  bool updateShouldNotify(QueryaUiZoomScope old) =>
      old.requested != requested || old.effective != effective;
}

extension QueryaUiZoomContext on BuildContext {
  /// The point of the app layout that sits under [windowPoint], a position in
  /// window coordinates such as a pointer event's `position`. The zoom is
  /// anchored at the top left, so this is a division. Use it before placing an
  /// overlay entry or a menu at a pointer position.
  Offset windowToApp(Offset windowPoint) {
    final zoom = QueryaUiZoomScope.maybeOf(this)?.effective ?? 1.0;
    return windowPoint / zoom;
  }
}

/// Zooms the whole interface by [scale]: the child is laid out in a window
/// `scale` times smaller and painted `scale` times larger, so text, icons,
/// paddings and hit areas grow together and every screen overflows (or not)
/// the same way at every scale.
///
/// The zoom is capped by [effectiveUiScale] and a change of [scale] is animated
/// over [duration] (pass [Duration.zero] for none). Dialogs, menus and tooltips
/// belong to the Navigator below this widget, so they are zoomed with it.
class QueryaUiZoom extends StatelessWidget {
  const QueryaUiZoom({
    super.key,
    required this.scale,
    required this.child,
    this.duration = const Duration(milliseconds: 180),
    this.curve = Curves.easeOutCubic,
  });

  final double scale;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = constraints.biggest;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: scale),
          duration: duration,
          curve: curve,
          child: child,
          builder: (context, animated, child) {
            // The layout is done once, for the zoom the change ends at; only
            // the painting follows the animation. Laying out at every step
            // re-wrapped text and moved cards on each frame, which read as
            // jumps. The window cap applies at once: a resize must not lag.
            return _Zoomed(
              requested: scale,
              layoutZoom: effectiveUiScale(requested: scale, window: window),
              paintZoom: effectiveUiScale(requested: animated, window: window),
              window: window,
              child: child!,
            );
          },
        );
      },
    );
  }
}

class _Zoomed extends StatelessWidget {
  const _Zoomed({
    required this.requested,
    required this.layoutZoom,
    required this.paintZoom,
    required this.window,
    required this.child,
  });

  final double requested;

  /// The zoom the layout is made for: the one an animation ends at.
  final double layoutZoom;

  /// The zoom the layout is painted at this frame.
  final double paintZoom;
  final Size window;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final logical = Size(window.width / layoutZoom, window.height / layoutZoom);
    final media = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    final inner = MediaQuery(
      data: media.copyWith(
        size: logical,
        padding: media.padding / layoutZoom,
        viewPadding: media.viewPadding / layoutZoom,
        viewInsets: media.viewInsets / layoutZoom,
        systemGestureInsets: media.systemGestureInsets / layoutZoom,
      ),
      child: QueryaUiZoomScope(
        requested: requested,
        effective: paintZoom,
        child: child,
      ),
    );
    return SizedBox(
      width: window.width,
      height: window.height,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Transform(
            alignment: Alignment.topLeft,
            transform: Matrix4.diagonal3Values(paintZoom, paintZoom, 1),
            child: SizedBox(
              width: logical.width,
              height: logical.height,
              child: inner,
            ),
          ),
        ),
      ),
    );
  }
}
