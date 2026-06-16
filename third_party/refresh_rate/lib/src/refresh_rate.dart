import 'dart:async';
import 'package:flutter/widgets.dart';

import 'generated/refresh_rate_api.g.dart';
import 'models/display_info.dart';
import 'models/enums.dart';
import 'refresh_rate_api_adapter.dart';
import 'verification/overlay_controller.dart';
import 'verification/refresh_rate_session.dart';

/// Primary entry-point for controlling and monitoring the display refresh rate.
///
/// All members are static; this class cannot be instantiated.
///
/// ### Quick-start
/// ```dart
/// // Unlock the highest supported refresh rate.
/// await RefreshRate.refresh();
/// RefreshRate.preferMax();
///
/// // Show an FPS overlay for debugging.
/// RefreshRate.showFPS();
/// ```
class RefreshRate {
  RefreshRate._();

  static RefreshRateApiAdapter _api = PigeonRefreshRateApiAdapter();
  static DisplayInfo _cachedInfo = DisplayInfo.fallback;
  static StreamController<DisplayInfo>? _changedController;
  static final _flutterApi = _RefreshRateFlutterApiImpl();

  // ── Platform registration ──────────────────────────────────────

  /// Replaces the default platform API adapter.
  ///
  /// Called by platform-specific entrypoints (e.g. the web plugin) during
  /// framework initialisation.  Not intended for end-user consumption.
  static void registerAdapter(RefreshRateApiAdapter adapter) {
    _api = adapter;
  }

  // ── Test seam ──────────────────────────────────────────────────

  /// Replaces the platform API implementation with a test fake.
  ///
  /// Call [clearApiForTesting] in `tearDown` to restore the real adapter.
  @visibleForTesting
  static void setApiForTesting(RefreshRateApiAdapter api) {
    _api = api;
  }

  /// Restores the real platform API and resets all internal state.
  ///
  /// Must be called in `tearDown` after [setApiForTesting].
  @visibleForTesting
  static void clearApiForTesting() {
    _api = PigeonRefreshRateApiAdapter();
    _flutterApi._onChanged = null;
    RefreshRateFlutterApi.setUp(null);
    _changedController?.close();
    _changedController = null;
  }

  // ── Control ────────────────────────────────────────────────────

  /// Opts the app into the platform's high-refresh-rate rendering pipeline.
  ///
  /// On Android this sets `preferredDisplayModeId` on the window surface.
  /// On iOS/macOS this adjusts `CADisplayLink` preferred frame rate ranges.
  /// Has no effect on platforms that do not support variable refresh rates.
  static void enable() {
    _api.enable();
    _refreshInfo();
  }

  /// Reverts the app to the platform default (typically 60 Hz).
  ///
  /// On iOS this allows the OS to manage the frame rate automatically.
  static void disable() {
    _api.disable();
    _refreshInfo();
  }

  /// Requests the maximum supported refresh rate for this display.
  ///
  /// Equivalent to calling [enable] then letting the platform pick the ceiling.
  static void preferMax() => _api.preferMax();

  /// Reverts to the display's default / preferred refresh rate.
  static void preferDefault() => _api.preferDefault();

  /// Requests a refresh rate that matches the given [fps] content rate.
  ///
  /// Useful when playing back video at a fixed frame rate (e.g. 24, 30, 60 fps)
  /// so the display cadence aligns with the media cadence.
  static void matchContent(double fps) => _api.matchContent(fps);

  /// Temporarily boosts the display to its maximum refresh rate for [duration].
  ///
  /// Commonly used when a gesture or animation starts — the display snaps to
  /// high-Hz immediately and returns to the preferred rate after the duration.
  static void boost(Duration duration) =>
      _api.boost(duration.inMilliseconds);

  /// Boosts the refresh rate for the lifetime of an [AnimationController].
  ///
  /// Registers a status listener that calls [boost] whenever the controller
  /// starts animating, and removes itself once the animation is done.
  static void boostDuring(AnimationController controller) {
    late final void Function(AnimationStatus) statusListener;
    statusListener = (status) {
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.reverse) {
        _api.boost(controller.duration?.inMilliseconds ?? 500);
      } else if (status == AnimationStatus.completed ||
                 status == AnimationStatus.dismissed) {
        controller.removeStatusListener(statusListener);
      }
    };
    controller.addStatusListener(statusListener);
  }

  /// Sets a named [RateCategory] hint for the display scheduler.
  ///
  /// Categories let you declare the performance class of your app
  /// (`low`, `normal`, `high`) rather than specifying raw Hz values.
  static void category(RateCategory c) => _api.setCategory(c.index);

  /// Enables or disables an automatic boost whenever the user touches the screen.
  ///
  /// When [enabled] is `true` the platform raises the refresh rate on every
  /// touch-down event and lowers it again after a short idle period.
  static void setTouchBoost(bool enabled) => _api.setTouchBoost(enabled);

  // ── Verification overlays ──────────────────────────────────────

  /// Shows a minimal live FPS counter overlay in the top-right corner.
  static void showFPS() => OverlayController.instance.showFPS();

  /// Shows a minimal live Hz readout overlay in the top-right corner.
  static void showHz() => OverlayController.instance.showHz();

  /// Shows the full diagnostic overlay (FPS + Hz + thermal state).
  static void showOverlay() => OverlayController.instance.showFull();

  /// Hides whatever verification overlay is currently visible.
  static void hideOverlay() => OverlayController.instance.hide();

  /// Whether the debug overlay is currently shown.
  static bool get isOverlayVisible => OverlayController.instance.isVisible;

  // ── Diagnostics ────────────────────────────────────────────────

  /// The most recently fetched [DisplayInfo] snapshot.
  ///
  /// Initialised to [DisplayInfo.fallback] (60 Hz, all optional fields null)
  /// until [refresh] is awaited at least once.
  static DisplayInfo get info => _cachedInfo;

  /// Fetches fresh [DisplayInfo] from the platform and caches the result.
  ///
  /// Resolves with the updated [DisplayInfo] on success.
  static Future<DisplayInfo> refresh() async {
    final msg = await _api.getDisplayInfo();
    _cachedInfo = DisplayInfo.fromMessage(msg);
    return _cachedInfo;
  }

  /// A broadcast stream that emits a new [DisplayInfo] whenever the display
  /// configuration changes (e.g. the user enables Low Power Mode, or the
  /// device throttles under thermal pressure).
  static Stream<DisplayInfo> get onChanged {
    if (_changedController == null) {
      _changedController = StreamController<DisplayInfo>.broadcast();
      _flutterApi._onChanged = (info) {
        _cachedInfo = info;
        _changedController!.add(info);
      };
      RefreshRateFlutterApi.setUp(_flutterApi);
    }
    return _changedController!.stream;
  }

  /// Whether iOS ProMotion (adaptive 120 Hz) is enabled for this app.
  ///
  /// Returns `false` until a successful [refresh] is completed and the device
  /// is an iPhone/iPad with a ProMotion display.
  static bool get isProMotionReady =>
      _cachedInfo.iosProMotionEnabled == true;

  /// Whether the device is currently in Low Power Mode.
  ///
  /// Defaults to `false` when the value cannot be determined.
  static bool get isLowPowerMode =>
      _cachedInfo.isLowPowerMode ?? false;

  /// The current thermal state of the device.
  ///
  /// A state of [ThermalState.serious] or [ThermalState.critical] may cause
  /// the OS to clamp the refresh rate regardless of your requested value.
  static ThermalState get thermalState => _cachedInfo.thermalState;

  // ── Benchmark sessions ─────────────────────────────────────────

  /// Creates and starts a new FPS benchmark session named [name].
  ///
  /// Call [RefreshRateSession.end] when the scenario under test completes to
  /// receive a [SessionReport] with verdict, FPS stats, and bottleneck hints.
  static RefreshRateSession startSession(String name) {
    return RefreshRateSession.create(name, _cachedInfo);
  }

  // ── Internal ───────────────────────────────────────────────────

  static void _refreshInfo() {
    void handle(DisplayInfoMessage msg) {
      _cachedInfo = DisplayInfo.fromMessage(msg);
    }
    void handleError(Object e) {
      assert(() {
        debugPrint('RefreshRate: _refreshInfo error: $e');
        return true;
      }());
    }

    try {
      final result = _api.getDisplayInfo();
      if (result is Future<DisplayInfoMessage>) {
        result.then(handle).catchError(handleError);
      } else {
        handle(result);
      }
    } catch (e) {
      handleError(e);
    }
  }
}

class _RefreshRateFlutterApiImpl extends RefreshRateFlutterApi {
  void Function(DisplayInfo)? _onChanged;

  @override
  void onDisplayInfoChanged(DisplayInfoMessage info) {
    _onChanged?.call(DisplayInfo.fromMessage(info));
  }
}
