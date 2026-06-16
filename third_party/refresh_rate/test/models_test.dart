import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/src/models/enums.dart';
import 'package:refresh_rate/src/models/display_info.dart';
import 'package:refresh_rate/src/models/session_report.dart';
import 'package:refresh_rate/src/generated/refresh_rate_api.g.dart';

void main() {
  group('DisplayInfo.fromMessage', () {
    test('maps all fields correctly', () {
      final msg = DisplayInfoMessage(
        currentRate: 120.0,
        maxRate: 120.0,
        minRate: 60.0,
        supportedRates: [60.0, 120.0],
        isVariableRefreshRate: true,
        engineTargetRate: 120.0,
        iosProMotionEnabled: true,
        androidApiLevel: null,
        isLowPowerMode: false,
        thermalStateIndex: 0,
        hasAdaptiveRefreshRate: true,
        displayServer: null,
        monitorCount: null,
      );
      final info = DisplayInfo.fromMessage(msg);
      expect(info.currentRate, 120.0);
      expect(info.thermalState, ThermalState.nominal);
      expect(info.isVariableRefreshRate, true);
    });

    test('handles null thermalStateIndex as unknown', () {
      final msg = DisplayInfoMessage(
        currentRate: 60.0, maxRate: 60.0, minRate: 60.0,
        supportedRates: [60.0], isVariableRefreshRate: false,
        engineTargetRate: 60.0,
        thermalStateIndex: null,
      );
      final info = DisplayInfo.fromMessage(msg);
      expect(info.thermalState, ThermalState.unknown);
    });
  });

  group('ThermalState', () {
    test('fromIndex maps correctly', () {
      expect(ThermalState.fromIndex(0), ThermalState.nominal);
      expect(ThermalState.fromIndex(1), ThermalState.fair);
      expect(ThermalState.fromIndex(2), ThermalState.serious);
      expect(ThermalState.fromIndex(3), ThermalState.critical);
      expect(ThermalState.fromIndex(null), ThermalState.unknown);
    });
  });

  group('SessionReport.toCsv', () {
    test('escapes commas in sessionName', () {
      final report = SessionReport(
        sessionName: 'feed, scroll',
        verdict: Verdict.good,
        likelyBottleneck: Bottleneck.none,
        targetHz: 120.0,
        observedAvgHz: 118.0,
        frameBudgetMs: 8.33,
        avgFps: 118.0,
        onePercentLowFps: 90.0,
        fivePercentLowFps: 100.0,
        avgBuildMs: 3.0,
        avgRasterMs: 4.0,
        avgTotalFrameMs: 7.0,
        jankyFrameCount: 2,
        severeJankCount: 0,
        missedFramePercent: 1.5,
        validDuration: Duration(seconds: 5),
        excludedDuration: Duration.zero,
        exclusionReasons: {},
        deviceState: DeviceStateSnapshot(thermalState: ThermalState.nominal),
      );
      final csv = report.toCsv();
      final lines = csv.split('\n');
      expect(lines.length, 2);
      // The escaped session name should appear in the values row
      expect(lines[1], contains('"feed, scroll"'));
    });
  });
}
