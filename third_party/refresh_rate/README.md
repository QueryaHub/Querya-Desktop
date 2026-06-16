# refresh_rate

[![pub package](https://img.shields.io/pub/v/refresh_rate.svg)](https://pub.dev/packages/refresh_rate)
[![pub points](https://img.shields.io/pub/points/refresh_rate)](https://pub.dev/packages/refresh_rate/score)
[![likes](https://img.shields.io/pub/likes/refresh_rate)](https://pub.dev/packages/refresh_rate/score)
[![popularity](https://img.shields.io/pub/popularity/refresh_rate)](https://pub.dev/packages/refresh_rate/score)
[![License: BSD-3](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://github.com/qoder-official/refresh_rate/blob/main/LICENSE)

**Unlock your device's full refresh rate in one line of Flutter.**

Your Flutter app runs at 60 Hz on a 120 Hz phone right now. The engine never tells the OS compositor it can handle more. `refresh_rate` fixes that — and gives you diagnostics, benchmarks, and a live overlay to prove it.

```dart
void main() {
  RefreshRate.enable();          // that's it — 120 Hz on a 120 Hz device
  runApp(const MyApp());
}
```

> **Why does this happen?** Flutter's engine never calls Android's `Surface.setFrameRate()` and the default iOS template is missing the `CADisableMinimumFrameDurationOnPhone` plist key. See [Flutter #160952](https://github.com/flutter/flutter/issues/160952). This package makes those calls for you.

Built on [pigeon](https://pub.dev/packages/pigeon) — fully typed end-to-end, zero `MethodChannel` codec overhead.

---

## Platform support

| Platform | Unlock | Query | Overlay | Benchmark |
|:---------|:------:|:-----:|:-------:|:---------:|
| **Android** 6+ (API 23) | ✅ | ✅ | ✅ | ✅ |
| **iOS** 15+ (ProMotion) | ✅ \* | ✅ | ✅ | ✅ |
| **macOS** 14+ (Sonoma) | ✅ | ✅ | ✅ | ✅ |
| **macOS** < 14 | — | ✅ | ✅ | ✅ |
| **Windows** | — | ✅ | ✅ | ✅ |
| **Linux** | — | ✅ | ✅ | ✅ |

\* iOS requires `Info.plist` key — see [iOS setup](#ios-setup).

---

## Installation

```yaml
dependencies:
  refresh_rate: ^1.0.0
```

### iOS setup

Add to `ios/Runner/Info.plist` — required for > 60 Hz on iPhones with ProMotion:

```xml
<key>CADisableMinimumFrameDurationOnPhone</key>
<true/>
```

Without this key, iOS caps your app at 60 Hz even on 120 Hz hardware. The plugin detects this at runtime and prints a console warning if missing. iPad Pro does **not** need this key.

---

## Quick start

```dart
import 'package:refresh_rate/refresh_rate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RefreshRate.enable();   // unlocks peak rate on every supported device
  runApp(const MyApp());
}
```

One call in `main()`. On a 120 Hz device your app now renders at 120 Hz. On a 60 Hz device nothing changes — the OS stays in control.

---

## Diagnostics

```dart
final info = RefreshRate.info;         // synchronous cached snapshot

print(info.currentRate);               // 120.0
print(info.maxRate);                   // 120.0
print(info.supportedRates);            // [60.0, 90.0, 120.0]
print(info.isVariableRefreshRate);     // true (LTPO panel)
print(info.androidApiLevel);           // 34 (Android only)
print(info.displayServer);             // "wayland" (Linux only)

print(RefreshRate.isLowPowerMode);     // false
print(RefreshRate.thermalState);       // ThermalState.nominal
print(RefreshRate.isProMotionReady);   // true — plist key + hardware both present

await RefreshRate.refresh();           // reload platform cache

RefreshRate.onChanged.listen((info) {  // rate, Low Power Mode, or thermal change
  print('Now running at ${info.currentRate} Hz');
});
```

---

## Advanced control

```dart
RefreshRate.preferMax();                          // highest available rate
RefreshRate.preferDefault();                      // return to OS default
RefreshRate.matchContent(24.0);                   // sync to 24 fps video (fixes judder)
RefreshRate.boost(const Duration(seconds: 2));    // temporary spike for gestures

// Android 15+
RefreshRate.category(RateCategory.high);          // semantic rate category
RefreshRate.setTouchBoost(true);                  // OS-managed touch boost
```

---

## Debug overlay

Drop a live performance HUD into any debug build:

```dart
if (kDebugMode) RefreshRate.showOverlay();
```

The overlay is **refresh-rate-aware**: FPS is colour-coded against the device's *actual* target Hz, not a hard-coded 60 Hz baseline. It also shows per-frame build/raster timings, frame budget, Low Power Mode, and thermal state.

```dart
RefreshRate.showFPS();       // just the FPS counter
RefreshRate.showHz();        // just the Hz badge
RefreshRate.showOverlay();   // full diagnostic panel
RefreshRate.hideOverlay();   // dismiss
```

---

## Benchmark sessions

Record a named performance window and get a structured report:

```dart
final session = RefreshRate.startSession('home_scroll');

// ... user interacts ...

final report = await session.end();

print(report.verdict);             // Verdict.good / degraded / poor
print(report.likelyBottleneck);    // Bottleneck.rasterBound / buildBound / none
print(report.avgFps);              // 108.4
print(report.onePercentLowFps);    // 87.2
print(report.missedFramePercent);  // 3.2%

final json = report.toJson();      // export for CI / QA dashboards
```

Sessions automatically exclude app backgrounding, resume warmup, Low Power Mode toggles, and thermal state changes — so numbers reflect real rendering performance.

---

## How it works

### Android

| API Level | What the plugin calls |
|:---------:|:----------------------|
| **34+** | `SurfaceControl.Transaction.setFrameRate()` — direct SurfaceFlinger vote |
| **30–33** | `preferredRefreshRate` + `preferredDisplayModeId` — dual hint |
| **23–29** | `preferredDisplayModeId` with resolution-match guard — legacy fallback |

Flutter never calls `Surface.setFrameRate()`. That single missing call is why 120 Hz phones render Flutter at 60 Hz.

### iOS

Sets `CADisplayLink.preferredFrameRateRange` with the device max. Validates the `CADisableMinimumFrameDurationOnPhone` plist key at runtime and warns loudly if missing.

### macOS

`NSView.displayLink` with `preferredFrameRateRange` on macOS 14+. Falls back to `NSScreen.maximumFramesPerSecond` / `CGDisplayCopyDisplayMode` for query.

### Windows & Linux

Query-only via `QueryDisplayConfig` (Win) and `gdk_monitor_get_refresh_rate` (Linux). Control depends on Flutter's desktop embedder evolution — tracked at [#93058](https://github.com/flutter/flutter/issues/93058) and [#183703](https://github.com/flutter/flutter/issues/183703).

---

## API reference

| Method | What it does |
|:-------|:-------------|
| `enable()` | Unlock peak rate — call once in `main()` |
| `disable()` | Stop overriding, return to OS default |
| `preferMax()` | Request highest available rate |
| `preferDefault()` | Clear rate override |
| `matchContent(fps)` | Sync display cadence to content frame rate |
| `boost(duration)` | Temporary max-rate spike |
| `category(cat)` | Android 15 semantic rate category |
| `setTouchBoost(bool)` | Android 15 touch-driven boost |
| `refresh()` | Reload platform info cache |
| `info` | Cached `RefreshRateInfo` snapshot |
| `isLowPowerMode` | Battery Saver / Low Power Mode active |
| `thermalState` | `ThermalState` enum |
| `isProMotionReady` | iOS plist key + ProMotion hardware |
| `onChanged` | `Stream<RefreshRateInfo>` |
| `showFPS()` | Live FPS counter overlay |
| `showHz()` | Live Hz badge overlay |
| `showOverlay()` | Full diagnostic overlay |
| `hideOverlay()` | Dismiss overlay |
| `startSession(name)` | Start benchmark session |

---

## Why this exists

Flutter's engine (Impeller since 3.24) *can* render at 120 Hz. But it never *tells the OS*. On Android, `Surface.setFrameRate()` returns zero search results across the entire engine codebase. On iOS, the engine code is correct but the default template omits the plist key.

This has been open since January 2023 ([#119268](https://github.com/flutter/flutter/issues/119268)), currently tracked at [#160952](https://github.com/flutter/flutter/issues/160952) (P2, unassigned).

`refresh_rate` fixes this today on shipping apps, while collecting real-device evidence for an eventual engine-level fix.

---

## License

BSD 3-Clause &copy; 2026 [Qoder](https://qoder.in)

---

<p align="center">
  Made with care by <a href="https://qoder.in">Qoder</a>&ensp;&middot;&ensp;<a href="https://pub.dev/publishers/qoder.in/packages">More packages</a>
</p>
