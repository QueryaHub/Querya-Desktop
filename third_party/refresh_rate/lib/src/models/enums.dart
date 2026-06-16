/// Indicates the desired performance category for the display scheduler.
///
/// Use [RefreshRate.category] to apply one of these hints to the platform.
enum RateCategory {
  /// No refresh-rate hint — the platform decides.
  none,

  /// Prefer a low refresh rate (e.g. reading, static UIs).
  low,

  /// Prefer the standard refresh rate (default).
  normal,

  /// Prefer the highest supported refresh rate
  /// (games, animations, scrolling at high speed).
  high;

  /// Returns the [RateCategory] matching [index], or [none] if unknown.
  static RateCategory fromIndex(int? index) {
    switch (index) {
      case 0: return none;
      case 1: return low;
      case 2: return normal;
      case 3: return high;
      default: return none;
    }
  }
}

/// The thermal condition of the device, as reported by the OS.
///
/// Higher-severity states may cause the OS to throttle the display
/// refresh rate regardless of what the app requests.
enum ThermalState {
  /// The device is well within thermal limits — full performance available.
  nominal,

  /// The device is slightly warm; minor throttling may apply.
  fair,

  /// The device is hot; significant throttling is likely.
  serious,

  /// The device is critically hot; the OS may force-reduce refresh rate.
  critical,

  /// Thermal state could not be determined (unsupported platform).
  unknown;

  /// Returns the [ThermalState] matching [index], or [unknown] if not found.
  static ThermalState fromIndex(int? index) {
    switch (index) {
      case 0: return nominal;
      case 1: return fair;
      case 2: return serious;
      case 3: return critical;
      default: return unknown;
    }
  }
}

/// Lifecycle state of a [RefreshRateSession] benchmark.
enum SessionState {
  /// The session has not yet started collecting data.
  idle,

  /// The session is actively collecting frame timings.
  running,

  /// The session is in a brief warm-up period after the app resumed.
  warmup,

  /// The session was paused due to the app going to the background.
  interrupted,

  /// The session has finished and a [SessionReport] is available.
  completed,
}

/// Reason why a time window was excluded from a [SessionReport].
enum ExclusionReason {
  /// App moved to the background.
  appBackgrounded,

  /// App became inactive (e.g. notification tray opened).
  appInactive,

  /// A brief warm-up window after the app resumed from background.
  resumeWarmup,

  /// Overlay opened or the window lost focus.
  overlayOrFocusLoss,

  /// The display refresh rate changed mid-session.
  displayRateChanged,

  /// Low Power Mode was toggled mid-session.
  lowPowerModeChanged,

  /// The thermal state changed mid-session.
  thermalStateChanged,
}

/// Overall quality verdict produced by [SessionReport].
enum Verdict {
  /// Frame rate is consistently at or near the target Hz.
  excellent,

  /// Frame rate is mostly stable with minor drops.
  good,

  /// Frame rate is acceptable but below optimal.
  fair,

  /// Frequent frame drops — the app misses its target regularly.
  poor,

  /// Not enough valid data to make a determination.
  inconclusive,
}

/// The most likely rendering bottleneck identified by [SessionReport].
enum Bottleneck {
  /// The UI/build thread is the constraint (slow widget tree rebuilds).
  buildBound,

  /// The raster thread is the constraint (complex paint operations).
  rasterBound,

  /// The display hardware is capping the achievable frame rate.
  displayCapped,

  /// Low Power Mode or battery saver is limiting performance.
  powerLimited,

  /// Thermal throttling is reducing the achievable frame rate.
  thermalLimited,

  /// No significant bottleneck detected.
  none,
}
