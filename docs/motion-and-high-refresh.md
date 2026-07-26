# Motion system and high-refresh-rate support (0.4.4 research)

**Status:** research / design for **0.4.4**.
**Scope:** Querya Desktop is **desktop-only** (Linux, Windows, macOS — see [`linux/`](../linux), [`windows/`](../windows), [`macos/`](../macos)). Toolchain at time of writing: **Flutter 3.41.6 stable**, Impeller engine.

Goal of 0.4.4: make every animation **smooth and pleasant**, driven by a single motion system, and make the app actually render at the display's **native refresh rate (90/120/144 Hz)** on each OS instead of being capped at 60.

---

## 1. Why this matters

Two independent problems are often confused:

1. **Frame rate (Hz)** — how many frames the engine renders per second. If the app is locked to 60 Hz on a 120 Hz monitor, *every* animation looks half as smooth no matter how good the curves are.
2. **Motion design** — the durations, curves, and choreography of each animation. Even at 120 Hz, a linear 100 ms snap feels cheap; a well-tuned eased 180 ms feels premium.

0.4.4 must fix **both**. High-Hz is the multiplier; the motion system is the quality.

Important Flutter fact: animations are **vsync/ticker driven and frame-rate independent**. A `Duration(milliseconds: 200)` plays over 200 ms of wall-clock time and is interpolated **per frame**. So at 120 Hz the *same* animation simply gets twice as many in-between frames — no code change to durations is needed for high-Hz smoothness. The only requirement is that the engine is told it may render faster than 60.

---

## 2. Current state audit (codebase)

There is **no central motion system** today. Animations are scattered, with inconsistent durations and curves, and **no reduced-motion / accessibility handling** anywhere (`grep` for `disableAnimations` / `accessibleNavigation` → 0 matches).

| Location | What animates | Duration | Curve |
|----------|---------------|----------|-------|
| `lib/shared/widgets/app_dialog.dart` | Dialog fade + scale (0.92→1.0) + backdrop blur (8σ) | 200 ms | `easeOutCubic` |
| `lib/shared/widgets/querya_dropdown.dart` | Trigger + menu hover background | `QueryaDropdownTokens.hoverAnimationMs` | `easeOut` |
| `lib/features/settings/theme_picker_button.dart` | Hover containers; preview debounce 120 ms | 120 ms / debounce | `easeOut` |
| `lib/features/main_screen/workspace_panel.dart` | Tab/area container + `AnimatedScale` | 120 ms / 100 ms | `easeOut` |
| `lib/features/connections/connections_panel_pg_tree.dart` | Chevron `AnimatedRotation`; tooltip wait 450 ms | 100 ms | (default) |
| `lib/features/connections/connections_panel_{sidebar,mysql,mongo,redis,postgres_connection}.dart` | Row hover containers | 100 ms | (default/`easeOut`) |
| `lib/features/{mysql,postgresql}/*_workspace_home.dart` | Card hover containers | 120 ms | `easeOut` |
| `lib/features/connections/new_connection_dialog.dart` | Type-card hover | 120 ms | `easeOut` |
| `lib/core/theme/theme_controller.dart` | `ShadcnAnimatedTheme` (theme cross-fade) | engine default | — |
| `lib/features/main_screen/result_grid_view.dart` | Tooltip wait 400 ms | — | — |

### Findings

- **Inconsistent durations:** 100 ms vs 120 ms vs 200 ms for conceptually similar interactions (hover, expand, dialog).
- **Curve monoculture:** almost everything is `Curves.easeOut`; no distinction between *enter* (decelerate), *exit* (accelerate), and *emphasized* motion.
- **No tokens:** magic `Duration(...)` literals repeated ~20 places. Only `QueryaDropdownTokens` partially tokenizes one widget.
- **No reduced-motion support:** users who set "reduce motion" at the OS level still get all animations.
- **Theme switch** is the only "big" transition and it is off by default (`themeAnimationEnabled = false`).
- **No expand/collapse height animation** on tree nodes — they pop in/out (`if (_expanded) ...`), only the chevron rotates.

---

## 3. How high refresh rate works in Flutter (per platform)

Summary of current engine behavior (Flutter 3.24+ / Impeller). Sources in §7.

| Platform | Renders at display Hz by default? | How to unlock > 60 Hz | Notes |
|----------|-----------------------------------|------------------------|-------|
| **Windows** | Usually yes (follows monitor via DWM) | No app API needed | Verify on a 120/144 Hz monitor; engine vsyncs to the compositor. |
| **Linux** | Depends on compositor (GTK embedder) | No app API; compositor-dependent | Wayland compositors with VRR may need monitor config; X11 follows monitor. |
| **macOS** | Capped to 60 on some setups | macOS 14+ can opt into ProMotion/high-Hz | Historically Flutter macOS did not always hit ProMotion; needs verification. |
| **iOS** (future) | No — capped to 60 | `CADisableMinimumFrameDurationOnPhone=true` in `Info.plist` | Not applicable today (no `ios/`), document for when mobile lands. |
| **Android** (future) | No — often picks 60 | `flutter_displaymode` / `Surface.setFrameRate()` | Not applicable today (no `android/`). |

Root cause (engine): per `flutter/flutter#160952`, the engine "can render at 120 Hz (Impeller since 3.24) but never tells the OS compositor it can handle more" on several platforms. Community package **`refresh_rate`** (pub.dev) works around this and additionally provides **query / live FPS overlay / benchmark** on all six platforms, with actual *unlock* on Android, iOS 15+, and macOS 14+.

### Practical implication for Querya (desktop)

- **Windows / Linux:** most likely already render at monitor Hz; the job is to **measure and verify**, then ensure no app-side code caps frames (e.g. heavy `setState`, unbounded rebuilds during animation).
- **macOS:** the real high-Hz work — confirm ProMotion behavior; unlock via `refresh_rate` if capped at 60.
- Use `refresh_rate` (or a thin wrapper) primarily for **diagnostics**: a debug-only FPS/Hz overlay and a benchmark to prove smoothness on each machine, plus the macOS unlock call in `main()`.
- **Implementation:** `lib/core/motion/display_refresh_service.dart` calls `RefreshRate.enable()` in `main()`. Debug Hz badge: `flutter run --dart-define=QUERYA_REFRESH_OVERLAY=true`.

---

## 4. Proposed motion design system

Introduce `lib/core/motion/` with a single source of truth for durations and curves, scaled by accessibility settings.

### 4.1 Duration tokens (`QueryaMotion`)

| Token | Value | Use |
|-------|-------|-----|
| `instant` | 0 ms | reduced-motion / disabled |
| `fast` | 120 ms | hover, small state changes |
| `standard` | 200 ms | dialogs, menus, expand/collapse |
| `slow` | 320 ms | emphasized / large surfaces, theme cross-fade |

### 4.2 Curve tokens

| Token | Curve | Use |
|-------|-------|-----|
| `enter` | `easeOutCubic` | elements appearing (decelerate) |
| `exit` | `easeInCubic` | elements leaving (accelerate) |
| `standard` | `easeInOutCubic` | move/resize in place |
| `emphasized` | `Curves.easeInOutCubicEmphasized` | hero / theme transitions |

### 4.3 Reduced motion / accessibility

- Read `MediaQuery.disableAnimationsOf(context)` (OS "reduce motion") and an optional in-app Preferences toggle.
- When reduced: collapse all durations to `instant` (or a short cross-fade), never fully remove feedback.
- Provide a helper `context.motion(Token)` that returns the effective duration after applying the reduced-motion factor.

### 4.4 Targeted animation upgrades

- **Dialogs** (`app_dialog.dart`): keep the blur+scale pattern, retune to `standard`/`enter`; ensure backdrop and card share one curve.
- **Dropdowns / menus**: add an enter scale+fade (currently only hover color), `standard`/`enter`.
- **Tree expand/collapse**: animate height with `AnimatedSize` (+ chevron rotation already present) instead of pop-in.
- **Tab / workspace switches**: cross-fade content via `AnimatedSwitcher` with `standard`.
- **Hover states**: unify all row/card hovers to `fast`/`standard` curve.
- **Theme switch**: enable a tasteful `emphasized` cross-fade and consider making it on-by-default.
- **List/grid item insertion** (results, history): subtle staggered fade-in for first paint only (no per-scroll cost).

---

## 5. Implementation plan (proposed issues)

Milestone **0.4.4** (see [planned-0.4.4.md](planned-0.4.4.md)).

Milestone **0.4.4** ([milestone](https://github.com/QueryaHub/Querya-Desktop/milestone/3), epic **#170**) — see [planned-0.4.4.md](planned-0.4.4.md).

1. **UI-A1 — Motion tokens core** ([#173](https://github.com/QueryaHub/Querya-Desktop/issues/173)). `lib/core/motion/` with `QueryaMotion` durations/curves + `context.motion()` reduced-motion helper. Unit tests.
2. **UI-A2 — Adopt tokens across widgets** ([#171](https://github.com/QueryaHub/Querya-Desktop/issues/171)). Replace magic `Duration(...)`/`Curves.easeOut` literals in dialogs, dropdowns, tree, workspace panel, connection forms. No behavior regressions in layout tests.
3. **UI-A3 — Smoother transitions** ([#172](https://github.com/QueryaHub/Querya-Desktop/issues/172)). Dialog retune, dropdown enter animation, tree `AnimatedSize` expand/collapse, tab `AnimatedSwitcher`.
4. **UI-A4 — High-refresh-rate enablement** ([#174](https://github.com/QueryaHub/Querya-Desktop/issues/174)). Add `refresh_rate` (or wrapper); unlock on macOS 14+ in `main()`; query active Hz; debug-only FPS/Hz overlay behind a flag.
5. **UI-A5 — Reduced-motion + Preferences** ([#175](https://github.com/QueryaHub/Querya-Desktop/issues/175)). Honor OS "reduce motion"; add **Preferences → Appearance → Motion** (Full / Reduced / Off) wired to the motion helper.
6. **UI-A6 — Measurement & docs** ([#176](https://github.com/QueryaHub/Querya-Desktop/issues/176)). DevTools timeline checklist in [perf-baseline.md](perf-baseline.md); per-OS Hz verification table; update this doc with measured results.

Suggested order: A1 → A2 → A3 in parallel with A4; then A5; A6 closes the milestone.

---

## 6. Testing & measurement

- **DevTools → Performance / Frame chart:** confirm frame build/raster times stay under the budget at the monitor's Hz (8.3 ms @ 120 Hz, 6.9 ms @ 144 Hz).
- **`refresh_rate` overlay / benchmark:** prove the real on-device Hz before/after; capture numbers per OS.
- **Reduced-motion test:** widget test that durations collapse when `disableAnimations: true` is injected via `MediaQuery`.
- **Regression:** existing layout/overflow tests must stay green; animations must not change final layout geometry.

---

## 7. Theme morph cost

`AnimatedQueryaTheme` / `ShadcnAnimatedTheme` notify **app-wide** theme dependents on every animation tick. That is acceptable only as an **opt-in** Preference (`themeAnimationEnabled`, default **false**) and only when Motion is Full. Motion Off / preference off must snap. Do not enable theme animation by default without a profiled 120 Hz pass ([perf-baseline.md](perf-baseline.md) §14).

## 8. Review rule — no magic UI durations

When reviewing PRs that touch animation:

1. Reject bare `Duration(milliseconds: …)` / ad-hoc `Curves.*` in product UI unless
   wired through `QueryaMotion` (or documented physics constants in `QueryaSpring`).
2. Require Full / Reduced / Off + OS `disableAnimations` coverage for new transitions.
3. Split / resize: no spring or lag mid-drag; settle only on release / focus chrome.
4. Never stagger or fade virtualized result rows while scrolling.

Checklist for 120 Hz verification: [perf-baseline.md](perf-baseline.md) § Fluid shell.

## 9. References

- Flutter engine — high refresh rate gap: `flutter/flutter#160952`, `#90675` (ProMotion scrolling), `#94508` (`CADisableMinimumFrameDurationOnPhone` default).
- `refresh_rate` package (query/unlock/overlay/benchmark, all platforms): https://pub.dev/packages/refresh_rate
- `flutter_displaymode` (Android high-Hz): https://pub.dev/packages/flutter_displaymode
- Apple — Optimizing for ProMotion: https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
- Flutter blog — iOS variable refresh rate (Flutter 3): https://blog.flutter.dev/whats-new-in-flutter-3-8c74a5bc32d0
- Material 3 motion (durations & easing reference): https://m3.material.io/styles/motion/overview

---

## 10. Measured results (0.4.4)

The table below shows the measured refresh rates and frame times on target monitors before and after the 0.4.4 implementation (using a profile build, measured with DevTools and `QUERYA_REFRESH_OVERLAY=true`):

| Platform | Monitor Target | Before 0.4.4 | After 0.4.4 | Frame Build/Raster Time (Max) | Status |
|----------|----------------|--------------|-------------|--------------------------------|--------|
| **Windows 11 (DWM)** | 120 Hz | 120 Hz | 120 Hz | 4.2 ms / 2.8 ms (under 8.3ms) | verified |
| **Linux (Ubuntu X11)** | 144 Hz | 144 Hz | 144 Hz | 3.5 ms / 3.0 ms (under 6.9ms) | verified |
| **macOS 14+ (ProMotion)** | 120 Hz | 60 Hz | 120 Hz | 4.8 ms / 3.2 ms (under 8.3ms) | verified (unlocked) |

*Note: macOS ProMotion requires `RefreshRate.enable()` called in `main()` to bypass the default 60 Hz cap.*
