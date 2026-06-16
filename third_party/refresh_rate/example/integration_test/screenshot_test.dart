import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:refresh_rate/refresh_rate.dart';

import 'package:refresh_rate_example/main.dart';

/// Waits for [finder] to match at least one widget, polling every 100 ms.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!finder.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 200));
}

/// Converts the Flutter surface to an image, pumps one frame, and
/// takes a named screenshot via the integration test binding.
Future<void> _captureScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await binding.convertFlutterSurfaceToImage();
  await tester.pump(const Duration(milliseconds: 200));
  await binding.takeScreenshot(name);
}

// ── Mock overlay widgets ─────────────────────────────────────────────────────
// The real FPS overlay shows "0 FPS" during integration tests because
// pump() doesn't generate real frame timings. These mock widgets render
// hardcoded values that represent a realistic 120Hz device scenario.

/// Mock FPS badge — identical styling to FpsOverlayWidget (showFPS) with
/// a hardcoded value showing a healthy 120 FPS readout.
Widget _mockFpsOverlay() {
  return Positioned(
    top: 0,
    right: 8,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: IgnorePointer(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xDD000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '120 FPS',
                style: TextStyle(
                  color: Color(0xFF4CAF50), // green — hitting target
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Mock Hz badge — identical styling to HzOverlayWidget.
Widget _mockHzOverlay() {
  return Positioned(
    top: 0,
    right: 8,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: IgnorePointer(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xDD000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '120Hz',
                style: TextStyle(
                  color: Color(0xFF64B5F6),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Wraps the example app with a mock overlay [widget] on top.
Widget _appWithOverlay(Widget overlay) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        const RefreshRateExampleApp(),
        overlay,
      ],
    ),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── 1. overlay — FPS counter showing 120 FPS in green ────────────────────
  testWidgets('screenshot: fps', (tester) async {
    await tester.pumpWidget(_appWithOverlay(_mockFpsOverlay()));
    await tester.pump(const Duration(seconds: 1));

    await _waitFor(tester, find.text('Diagnostic Console'));

    // Enable high refresh so the hero panel shows real 120 Hz data.
    RefreshRate.enable();
    await tester.pump(const Duration(seconds: 2));

    await _captureScreenshot(binding, tester, 'fps');
  });

  // ── 2. before_after — Hz badge showing 120Hz ────────────────────────────
  testWidgets('screenshot: hz', (tester) async {
    await tester.pumpWidget(_appWithOverlay(_mockHzOverlay()));
    await tester.pump(const Duration(seconds: 1));

    await _waitFor(tester, find.text('Diagnostic Console'));

    RefreshRate.enable();
    await tester.pump(const Duration(seconds: 2));

    await _captureScreenshot(binding, tester, 'hz');
  });
}
