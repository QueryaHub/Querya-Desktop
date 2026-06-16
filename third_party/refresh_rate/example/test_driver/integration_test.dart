import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Flutter Drive driver for screenshot capture.
///
/// Receives screenshot bytes from the device and writes them to the package
/// root `screenshots/` directory (one level up from `example/`).
///
/// Run from the package root via `scripts/take_screenshots.sh`, or manually:
///
///   cd example
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/screenshot_test.dart \
///     -d [device-id]
Future<void> main() => integrationDriver(
      onScreenshot: (
        String name,
        List<int> screenshotBytes, [
        Map<String, Object?>? args,
      ]) async {
        final dir = Directory('../screenshots');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final file = File('../screenshots/$name.png');
        await file.writeAsBytes(screenshotBytes);
        stdout.writeln('  screenshot saved → screenshots/$name.png');
        return true;
      },
    );
