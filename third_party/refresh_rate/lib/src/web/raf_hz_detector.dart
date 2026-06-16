import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Detects the display's refresh rate by measuring
/// `requestAnimationFrame` callback intervals.
///
/// Uses the same technique as TestUFO: collect a window of rAF
/// timestamps, compute the median inter-frame interval, and derive Hz.
class RafHzDetector {
  /// Number of frames to sample before reporting a result.
  static const int _kSampleCount = 120;

  /// Measures the current display refresh rate via rAF timing.
  ///
  /// Collects [_kSampleCount] frames, computes the median interval,
  /// and returns `1000 / medianMs`.  Returns `null` if measurement fails.
  static Future<double?> measure() {
    final completer = Completer<double?>();
    final timestamps = <double>[];
    late final JSFunction callback;

    void onFrame(JSNumber ts) {
      timestamps.add(ts.toDartDouble);

      if (timestamps.length >= _kSampleCount + 1) {
        // Compute intervals
        final intervals = <double>[];
        for (var i = 1; i < timestamps.length; i++) {
          intervals.add(timestamps[i] - timestamps[i - 1]);
        }
        intervals.sort();
        final median = intervals[intervals.length ~/ 2];

        if (median > 0) {
          // Round to nearest common Hz value (e.g. 60, 90, 120, 144, 165, 240)
          final rawHz = 1000.0 / median;
          completer.complete(_snapToCommonHz(rawHz));
        } else {
          completer.complete(null);
        }
      } else {
        web.window.requestAnimationFrame(callback);
      }
    }

    callback = onFrame.toJS;
    web.window.requestAnimationFrame(callback);

    return completer.future;
  }

  /// Snaps a raw Hz measurement to the nearest common display refresh rate
  /// when the raw value is within 3% tolerance.
  static double _snapToCommonHz(double raw) {
    const commonRates = [30.0, 48.0, 60.0, 72.0, 90.0, 120.0, 144.0, 165.0, 240.0, 360.0];
    for (final rate in commonRates) {
      if ((raw - rate).abs() / rate < 0.03) return rate;
    }
    return double.parse(raw.toStringAsFixed(1));
  }
}
