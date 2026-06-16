import '../generated/refresh_rate_api.g.dart';
import 'enums.dart';

/// A snapshot of the current display configuration and device health.
///
/// Retrieve a fresh snapshot via [RefreshRate.refresh] or listen to
/// [RefreshRate.onChanged] for real-time updates.
class DisplayInfo {
  /// The refresh rate the display is currently running at, in Hz.
  final double currentRate;

  /// The maximum refresh rate supported by this display, in Hz.
  final double maxRate;

  /// The minimum refresh rate supported by this display, in Hz.
  final double minRate;

  /// All refresh rates the display hardware can run at, in Hz.
  final List<double> supportedRates;

  /// Whether the display supports variable refresh rate (VRR / LTPO).
  final bool isVariableRefreshRate;

  /// The frame rate the Flutter engine is currently targeting, in Hz.
  final double engineTargetRate;

  /// Whether iOS ProMotion adaptive refresh is enabled for this app.
  ///
  /// `null` on non-iOS platforms.
  final bool? iosProMotionEnabled;

  /// The Android API level of the device.
  ///
  /// `null` on non-Android platforms.
  final int? androidApiLevel;

  /// Whether the device is in Low Power Mode.
  ///
  /// `null` when the platform does not expose this information.
  final bool? isLowPowerMode;

  /// The current thermal state of the device.
  final ThermalState thermalState;

  /// Whether the display supports an adaptive (variable) refresh rate.
  ///
  /// `null` when the platform does not expose this information.
  final bool? hasAdaptiveRefreshRate;

  /// The name of the display server in use (Linux only, e.g. `"wayland"`).
  ///
  /// `null` on non-Linux platforms.
  final String? displayServer;

  /// The number of monitors connected to the device (desktop platforms only).
  ///
  /// `null` on mobile platforms.
  final int? monitorCount;

  /// Creates a new [DisplayInfo] snapshot.
  const DisplayInfo({
    required this.currentRate,
    required this.maxRate,
    required this.minRate,
    required this.supportedRates,
    required this.isVariableRefreshRate,
    required this.engineTargetRate,
    this.iosProMotionEnabled,
    this.androidApiLevel,
    this.isLowPowerMode,
    required this.thermalState,
    this.hasAdaptiveRefreshRate,
    this.displayServer,
    this.monitorCount,
  });

  /// Creates a [DisplayInfo] from a platform [DisplayInfoMessage].
  factory DisplayInfo.fromMessage(DisplayInfoMessage msg) {
    return DisplayInfo(
      currentRate: msg.currentRate ?? 60.0,
      maxRate: msg.maxRate ?? 60.0,
      minRate: msg.minRate ?? 60.0,
      supportedRates: msg.supportedRates?.whereType<double>().toList() ?? const [60.0],
      isVariableRefreshRate: msg.isVariableRefreshRate ?? false,
      engineTargetRate: msg.engineTargetRate ?? 60.0,
      iosProMotionEnabled: msg.iosProMotionEnabled,
      androidApiLevel: msg.androidApiLevel,
      isLowPowerMode: msg.isLowPowerMode,
      thermalState: ThermalState.fromIndex(msg.thermalStateIndex),
      hasAdaptiveRefreshRate: msg.hasAdaptiveRefreshRate,
      displayServer: msg.displayServer,
      monitorCount: msg.monitorCount,
    );
  }

  /// A safe fallback [DisplayInfo] used before the first [RefreshRate.refresh]
  /// call completes. Assumes a standard 60 Hz non-VRR display.
  static const DisplayInfo fallback = DisplayInfo(
        currentRate: 60.0,
        maxRate: 60.0,
        minRate: 60.0,
        supportedRates: [60.0],
        isVariableRefreshRate: false,
        engineTargetRate: 60.0,
        thermalState: ThermalState.unknown,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplayInfo &&
          currentRate == other.currentRate &&
          maxRate == other.maxRate &&
          minRate == other.minRate &&
          isVariableRefreshRate == other.isVariableRefreshRate &&
          engineTargetRate == other.engineTargetRate &&
          thermalState == other.thermalState &&
          isLowPowerMode == other.isLowPowerMode;

  @override
  int get hashCode => Object.hash(currentRate, maxRate, minRate,
      isVariableRefreshRate, engineTargetRate, thermalState, isLowPowerMode);

  @override
  String toString() =>
      'DisplayInfo(currentRate: ${currentRate}Hz, maxRate: ${maxRate}Hz, '
      'thermalState: $thermalState, isLowPowerMode: $isLowPowerMode)';
}
