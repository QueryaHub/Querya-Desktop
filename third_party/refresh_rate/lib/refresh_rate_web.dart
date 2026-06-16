import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/refresh_rate.dart';
import 'src/web/web_refresh_rate_adapter.dart';

/// Web platform implementation of the RefreshRate plugin.
///
/// Uses `requestAnimationFrame` interval timing to detect the
/// display's current refresh rate (same technique as TestUFO).
/// Control methods are graceful no-ops because browsers own their
/// vsync scheduling and expose no API to change it.
///
/// ### What works on web
///
/// | Feature | Status |
/// |:--------|:------:|
/// | Query current Hz | ✓ (via rAF timing) |
/// | FPS overlay / benchmark | ✓ (pure Dart, unchanged) |
/// | Unlock / control rate | ✗ (browsers own vsync) |
/// | Supported rates / max rate | ✗ (not exposed) |
/// | Low Power Mode / thermal | ✗ (no web equivalent) |
class RefreshRateWeb {
  /// Registers the web plugin by swapping in [WebRefreshRateApiAdapter].
  static void registerWith(Registrar registrar) {
    RefreshRate.registerAdapter(WebRefreshRateApiAdapter());
  }
}
