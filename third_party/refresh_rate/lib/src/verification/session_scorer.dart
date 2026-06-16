import '../models/enums.dart';
import '../models/session_report.dart';
import 'fps_tracker.dart';

/// Utility class that calculates the final [SessionReport] metrics.
abstract class SessionScorer {
  /// Computes a [SessionReport] from the recorded tracking data.
  static SessionReport compute({
    required String sessionName,
    required FpsTracker tracker,
    required double targetHz,
    required Duration validDuration,
    required Duration excludedDuration,
    required Map<ExclusionReason, int> exclusionReasons,
    required DeviceStateSnapshot deviceState,
  }) {
    final frameBudgetMs = 1000.0 / targetHz;
    final avgFps = tracker.avgFps;
    final missed = tracker.missedFramePercent(targetHz);
    final one = tracker.onePercentLowFps;
    final five = tracker.fivePercentLowFps;
    final janky = tracker.jankyFrameCount(targetHz);
    final severe = tracker.severeJankCount(targetHz);
    final avgBuild = tracker.avgBuildMs;
    final avgRaster = tracker.avgRasterMs;
    final avgTotal = tracker.avgTotalMs;

    final verdict = _computeVerdict(avgFps, targetHz, missed);
    final bottleneck = _computeBottleneck(
      avgBuild: avgBuild,
      avgRaster: avgRaster,
      avgFps: avgFps,
      targetHz: targetHz,
      isLowPowerMode: deviceState.isLowPowerMode,
      thermalState: deviceState.thermalState,
    );

    return SessionReport(
      sessionName: sessionName,
      verdict: verdict,
      likelyBottleneck: bottleneck,
      targetHz: targetHz,
      observedAvgHz: avgFps,
      frameBudgetMs: frameBudgetMs,
      avgFps: avgFps,
      onePercentLowFps: one,
      fivePercentLowFps: five,
      avgBuildMs: avgBuild,
      avgRasterMs: avgRaster,
      avgTotalFrameMs: avgTotal,
      jankyFrameCount: janky,
      severeJankCount: severe,
      missedFramePercent: missed,
      validDuration: validDuration,
      excludedDuration: excludedDuration,
      exclusionReasons: exclusionReasons,
      deviceState: deviceState,
    );
  }

  static Verdict _computeVerdict(double avgFps, double targetHz, double missedPct) {
    if (avgFps == 0) return Verdict.inconclusive;
    final hitRate = avgFps / targetHz;
    if (hitRate >= 0.95 && missedPct < 2) return Verdict.excellent;
    if (hitRate >= 0.85 && missedPct < 5) return Verdict.good;
    if (hitRate >= 0.70 && missedPct < 15) return Verdict.fair;
    return Verdict.poor;
  }

  static Bottleneck _computeBottleneck({
    required double avgBuild,
    required double avgRaster,
    required double avgFps,
    required double targetHz,
    required bool? isLowPowerMode,
    required ThermalState thermalState,
  }) {
    if (isLowPowerMode == true) return Bottleneck.powerLimited;
    if (thermalState == ThermalState.serious || thermalState == ThermalState.critical) {
      return Bottleneck.thermalLimited;
    }
    final budgetMs = 1000.0 / targetHz;
    // 85-90% of target: likely a display-side cap (LTPO floor, VSync rounding, etc.)
    if (avgFps >= targetHz * 0.85 && avgFps < targetHz * 0.95) {
      return Bottleneck.displayCapped;
    }
    // Below 85%: check for build vs raster bottleneck
    if (avgFps < targetHz * 0.85) {
      if (avgBuild > avgRaster && avgBuild > budgetMs * 0.5) return Bottleneck.buildBound;
      if (avgRaster > budgetMs * 0.5) return Bottleneck.rasterBound;
    }
    return Bottleneck.none;
  }
}
