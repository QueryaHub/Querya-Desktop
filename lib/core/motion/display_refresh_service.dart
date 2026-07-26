import 'package:flutter/foundation.dart';
import 'package:refresh_rate/refresh_rate.dart';

/// Desktop display refresh-rate unlock and diagnostics (UI-A4 / #174).
///
/// Calls [RefreshRate.enable] once at startup:
/// - **macOS 14+:** ProMotion / high-Hz unlock
/// - **Windows:** typically follows DWM (enable is effectively a no-op unlock)
/// - **Linux:** **query-only** — enable is a no-op; [RefreshRate.info] / overlay
///   report GDK monitor refresh (compositor decides actual pacing)
///
/// Debug overlay: `flutter run --dart-define=QUERYA_REFRESH_OVERLAY=true`.
abstract final class DisplayRefreshService {
  static const bool _overlayFromEnvironment = bool.fromEnvironment(
    'QUERYA_REFRESH_OVERLAY',
  );

  /// Unlock peak refresh where the platform supports it; log Hz in debug builds.
  static void initialize() {
    RefreshRate.enable();

    if (!kDebugMode) return;

    _logRefreshInfo();
    if (displayRefreshOverlayEnabled(
      debugMode: kDebugMode,
      overlayFlag: _overlayFromEnvironment,
    )) {
      RefreshRate.showHz();
    }
  }

  static void _logRefreshInfo() {
    final info = RefreshRate.info;
    debugPrint(
      'Display refresh: ${info.currentRate} Hz '
      '(max ${info.maxRate}, variable=${info.isVariableRefreshRate})',
    );
  }

  /// Cached current refresh rate from the platform (Hz), when available.
  static double get currentHz => RefreshRate.info.currentRate;

  /// Peak supported refresh rate (Hz).
  static double get maxHz => RefreshRate.info.maxRate;

  @visibleForTesting
  static bool displayRefreshOverlayEnabled({
    required bool debugMode,
    required bool overlayFlag,
  }) =>
      debugMode && overlayFlag;
}
