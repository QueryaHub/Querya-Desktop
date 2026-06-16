import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'fps_tracker.dart';
import 'overlay_widgets.dart';

enum _OverlayMode { none, fps, hz, full }

/// Manages the visibility and rendering of debug overlays.
class OverlayController {
  OverlayController._();
  /// The singleton instance of [OverlayController].
  static final instance = OverlayController._();

  OverlayEntry? _entry;
  _OverlayMode _mode = _OverlayMode.none;
  final FpsTracker _tracker = FpsTracker();
  TimingsCallback? _timingsCallback;

  /// Whether an overlay is currently visible.
  bool get isVisible => _mode != _OverlayMode.none;

  /// Shows a compact FPS overlay.
  void showFPS() => _show(_OverlayMode.fps);
  /// Shows a compact Hz (refresh rate) overlay.
  void showHz() => _show(_OverlayMode.hz);
  /// Shows the full debug overlay with detailed metrics.
  void showFull() => _show(_OverlayMode.full);

  /// Hides any currently visible overlay.
  void hide() {
    _entry?.remove();
    _entry = null;
    _mode = _OverlayMode.none;
    _stopTracking();
  }

  void _show(_OverlayMode mode) {
    hide();
    _mode = mode;
    _startTracking();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlay = _findOverlay();
      if (overlay == null) return;
      _entry = OverlayEntry(builder: (_) => _buildWidget());
      overlay.insert(_entry!);
    });
  }

  // Walks DOWN the element tree to find the first OverlayState.
  // Overlay.maybeOf(rootElement) fails because the Overlay is a descendant,
  // not an ancestor, of the root element.
  static OverlayState? _findOverlay() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    OverlayState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is OverlayState) {
        found = element.state as OverlayState;
        return;
      }
      element.visitChildren(visit);
    }
    root.visitChildren(visit);
    return found;
  }

  Widget _buildWidget() {
    final inner = switch (_mode) {
      _OverlayMode.fps => FpsOverlayWidget(tracker: _tracker),
      _OverlayMode.hz => HzOverlayWidget(tracker: _tracker),
      _OverlayMode.full => FullOverlayWidget(tracker: _tracker),
      _OverlayMode.none => const SizedBox.shrink(),
    };
    return inner;
  }

  void _startTracking() {
    if (_timingsCallback != null) return;
    _timingsCallback = _tracker.addTimings;
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);
  }

  void _stopTracking() {
    if (_timingsCallback != null) {
      SchedulerBinding.instance.removeTimingsCallback(_timingsCallback!);
      _timingsCallback = null;
    }
    _tracker.reset();
  }
}
