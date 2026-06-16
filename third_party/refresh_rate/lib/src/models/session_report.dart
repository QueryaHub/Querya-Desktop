import 'dart:convert';
import 'enums.dart';

/// A point-in-time snapshot of device conditions recorded at session start.
///
/// Captured when a [RefreshRateSession] is created and embedded in the
/// resulting [SessionReport] so analysis can account for the environment.
class DeviceStateSnapshot {
  /// Whether the device was in Low Power Mode when the session started.
  ///
  /// `null` when the platform does not expose this information.
  final bool? isLowPowerMode;

  /// The thermal state of the device when the session started.
  final ThermalState thermalState;

  /// Whether the display supports an adaptive (variable) refresh rate.
  ///
  /// `null` when the platform does not expose this information.
  final bool? hasAdaptiveRefreshRate;

  /// The display server in use (Linux only, e.g. `"wayland"`).
  ///
  /// `null` on non-Linux platforms.
  final String? displayServer;

  /// Number of connected monitors (desktop platforms only).
  ///
  /// `null` on mobile platforms.
  final int? monitorCount;

  /// Creates a new [DeviceStateSnapshot].
  const DeviceStateSnapshot({
    this.isLowPowerMode,
    required this.thermalState,
    this.hasAdaptiveRefreshRate,
    this.displayServer,
    this.monitorCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceStateSnapshot &&
          isLowPowerMode == other.isLowPowerMode &&
          thermalState == other.thermalState;

  @override
  int get hashCode => Object.hash(isLowPowerMode, thermalState);

  /// Serializes this snapshot to a JSON-compatible map.
  Map<String, dynamic> toMap() => {
        'isLowPowerMode': isLowPowerMode,
        'thermalState': thermalState.name,
        'hasAdaptiveRefreshRate': hasAdaptiveRefreshRate,
        'displayServer': displayServer,
        'monitorCount': monitorCount,
      };
}

/// The result produced when a [RefreshRateSession] ends.
///
/// Contains FPS statistics, frame timing breakdowns, a performance [verdict],
/// a likely [likelyBottleneck] hint, and excluded-window details.
class SessionReport {
  /// The name given to the session when it was started.
  final String sessionName;

  /// Overall quality assessment for this session.
  final Verdict verdict;

  /// The rendering stage most likely responsible for any frame drops.
  final Bottleneck likelyBottleneck;

  /// The target refresh rate in Hz at the time the session began.
  final double targetHz;

  /// The average display refresh rate observed during the session, in Hz.
  final double observedAvgHz;

  /// The frame duration budget at [targetHz] (1000 / targetHz), in ms.
  final double frameBudgetMs;

  /// Average frames per second across all valid frames.
  final double avgFps;

  /// The 1st-percentile FPS (worst 1% of frames).
  final double onePercentLowFps;

  /// The 5th-percentile FPS (worst 5% of frames).
  final double fivePercentLowFps;

  /// Average build (UI thread) time per frame, in ms.
  final double avgBuildMs;

  /// Average raster thread time per frame, in ms.
  final double avgRasterMs;

  /// Average total frame time (build + raster), in ms.
  final double avgTotalFrameMs;

  /// Number of frames that exceeded the frame budget.
  final int jankyFrameCount;

  /// Number of frames that exceeded twice the frame budget.
  final int severeJankCount;

  /// Percentage of frames that were missed (janky), from 0–100.
  final double missedFramePercent;

  /// Total duration of valid (non-excluded) measurement time.
  final Duration validDuration;

  /// Total duration excluded from measurement (background, warmup, etc.).
  final Duration excludedDuration;

  /// A breakdown of how many times each [ExclusionReason] occurred.
  final Map<ExclusionReason, int> exclusionReasons;

  /// Device state recorded at the start of the session.
  final DeviceStateSnapshot deviceState;

  /// Creates a new [SessionReport].
  const SessionReport({
    required this.sessionName,
    required this.verdict,
    required this.likelyBottleneck,
    required this.targetHz,
    required this.observedAvgHz,
    required this.frameBudgetMs,
    required this.avgFps,
    required this.onePercentLowFps,
    required this.fivePercentLowFps,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.avgTotalFrameMs,
    required this.jankyFrameCount,
    required this.severeJankCount,
    required this.missedFramePercent,
    required this.validDuration,
    required this.excludedDuration,
    required this.exclusionReasons,
    required this.deviceState,
  });

  /// Serializes this report to a JSON-compatible map.
  Map<String, dynamic> toMap() => {
        'sessionName': sessionName,
        'verdict': verdict.name,
        'likelyBottleneck': likelyBottleneck.name,
        'targetHz': targetHz,
        'observedAvgHz': observedAvgHz,
        'frameBudgetMs': frameBudgetMs,
        'avgFps': avgFps,
        'onePercentLowFps': onePercentLowFps,
        'fivePercentLowFps': fivePercentLowFps,
        'avgBuildMs': avgBuildMs,
        'avgRasterMs': avgRasterMs,
        'avgTotalFrameMs': avgTotalFrameMs,
        'jankyFrameCount': jankyFrameCount,
        'severeJankCount': severeJankCount,
        'missedFramePercent': missedFramePercent,
        'validDurationMs': validDuration.inMilliseconds,
        'excludedDurationMs': excludedDuration.inMilliseconds,
        'exclusionReasons': exclusionReasons.map((k, v) => MapEntry(k.name, v)),
        'deviceState': deviceState.toMap(),
      };

  /// Serializes this report to a JSON string.
  String toJson() => jsonEncode(toMap());

  /// Serializes this report to a CSV string.
  String toCsv() {
    final m = toMap();
    String esc(dynamic v) {
      final s = v is Map ? jsonEncode(v) : '$v';
      if (s.contains(',') || s.contains('"') || s.contains('\n')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }
    final headers = m.keys.join(',');
    final values = m.values.map(esc).join(',');
    return '$headers\n$values';
  }
}
