import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/enums.dart';
import '../refresh_rate.dart';
import 'fps_tracker.dart';

mixin _OverlayStateMixin<T extends StatefulWidget> on State<T> {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker((_) => setState(() {}));
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Color fpsColor(double fps, double targetHz) {
    if (fps >= targetHz * 0.95) return const Color(0xFF4CAF50);
    if (fps >= targetHz * 0.75) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  Widget overlayContainer({required Widget child}) {
    return Positioned(
      top: MediaQueryData.fromView(View.of(context)).padding.top + 4,
      right: 8,
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xDD000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── FPS Badge ─────────────────────────────────────────────────────

/// A small overlay widget that displays the current FPS.
class FpsOverlayWidget extends StatefulWidget {
  /// The [FpsTracker] providing frame timings.
  final FpsTracker tracker;
  /// Creates a [FpsOverlayWidget].
  const FpsOverlayWidget({super.key, required this.tracker});
  @override
  State<FpsOverlayWidget> createState() => _FpsOverlayWidgetState();
}

class _FpsOverlayWidgetState extends State<FpsOverlayWidget>
    with _OverlayStateMixin {
  @override
  Widget build(BuildContext context) {
    final fps = widget.tracker.recentFps();
    return overlayContainer(
      child: Text(
        '${fps.toStringAsFixed(0)} FPS',
        style: TextStyle(
          color: fpsColor(fps, RefreshRate.info.maxRate),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ── Hz Badge ──────────────────────────────────────────────────────

/// A small overlay widget that displays the current display refresh rate.
class HzOverlayWidget extends StatefulWidget {
  /// The [FpsTracker] (unused but required for generic widget creation).
  final FpsTracker tracker;
  /// Creates a [HzOverlayWidget].
  const HzOverlayWidget({super.key, required this.tracker});
  @override
  State<HzOverlayWidget> createState() => _HzOverlayWidgetState();
}

class _HzOverlayWidgetState extends State<HzOverlayWidget>
    with _OverlayStateMixin {
  @override
  Widget build(BuildContext context) {
    final hz = RefreshRate.info.currentRate;
    return overlayContainer(
      child: Text(
        '${hz.toStringAsFixed(0)}Hz',
        style: const TextStyle(
          color: Color(0xFF64B5F6),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ── Full Diagnostic Overlay ────────────────────────────────────────

/// A larger overlay widget that displays FPS, build/raster times, and device health.
class FullOverlayWidget extends StatefulWidget {
  /// The [FpsTracker] providing frame timings.
  final FpsTracker tracker;
  /// Creates a [FullOverlayWidget].
  const FullOverlayWidget({super.key, required this.tracker});
  @override
  State<FullOverlayWidget> createState() => _FullOverlayWidgetState();
}

class _FullOverlayWidgetState extends State<FullOverlayWidget>
    with _OverlayStateMixin {
  @override
  Widget build(BuildContext context) {
    final fps = widget.tracker.recentFps();
    final buildMs = widget.tracker.avgBuildMs;
    final rasterMs = widget.tracker.avgRasterMs;
    final targetHz = RefreshRate.info.maxRate;
    final budgetMs = 1000.0 / targetHz;

    return overlayContainer(
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 11,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${fps.toStringAsFixed(0)} FPS',
              style: TextStyle(
                color: fpsColor(fps, targetHz),
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text('build ${buildMs.toStringAsFixed(1)}ms  raster ${rasterMs.toStringAsFixed(1)}ms'),
            Text('budget ${budgetMs.toStringAsFixed(1)}ms @ ${targetHz.toStringAsFixed(0)}Hz'),
            if (RefreshRate.isLowPowerMode)
              const Text(
                '\u26a1 Low Power',
                style: TextStyle(color: Color(0xFFFFCC02)),
              ),
            if (RefreshRate.thermalState != ThermalState.nominal &&
                RefreshRate.thermalState != ThermalState.unknown)
              Text(
                'thermal: ${RefreshRate.thermalState.name}',
                style: const TextStyle(color: Color(0xFFFF7043)),
              ),
          ],
        ),
      ),
    );
  }
}
