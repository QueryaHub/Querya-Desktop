# Planned release 0.4.4 — UI motion polish and high refresh rate

**Status:** **shipped in 0.4.4** (GitHub milestone [**0.4.4**](https://github.com/QueryaHub/Querya-Desktop/milestone/3), epic **#170** closed).  
**Depends on:** **0.4.3** theme follow-ups (shipped).
**Design doc:** [motion-and-high-refresh.md](motion-and-high-refresh.md) — research, current-state audit, and per-platform Hz behavior.

Theme: make every animation **smooth and pleasant** through one motion system, and make the app render at the display's **native refresh rate (90/120/144 Hz)** on Linux, Windows, and macOS instead of being capped at 60.

## Why

- Animations today are ad-hoc: inconsistent durations (100 / 120 / 200 ms), a single `easeOut` curve everywhere, ~20 magic `Duration(...)` literals, and **no reduced-motion handling**.
- Flutter animations are vsync-driven and frame-rate independent, so the smoothness win comes from (a) telling the engine it may exceed 60 Hz and (b) a cohesive motion design — see [motion-and-high-refresh.md §1–3](motion-and-high-refresh.md).

## Scope

| ID | Issue | Scope | Summary |
|----|-------|--------|---------|
| **UI-A1** | [#173](https://github.com/QueryaHub/Querya-Desktop/issues/173) | `motion`, `core` | **Motion tokens** — `lib/core/motion/` with `QueryaMotion` durations/curves and a `context.motion()` reduced-motion helper. |
| **UI-A2** | [#171](https://github.com/QueryaHub/Querya-Desktop/issues/171) | `motion`, `ui` | **Adopt tokens** — replace magic durations/curves in dialogs, dropdowns, tree, workspace panel, connection forms (no layout regressions). |
| **UI-A3** | [#172](https://github.com/QueryaHub/Querya-Desktop/issues/172) | `motion`, `ui` | **Smoother transitions** — dialog retune, dropdown enter animation, `AnimatedSize` tree expand/collapse, `AnimatedSwitcher` tab/content cross-fade. |
| **UI-A4** | [#174](https://github.com/QueryaHub/Querya-Desktop/issues/174) | `performance`, `platform` | **High refresh rate** — `refresh_rate` (or wrapper): unlock on macOS 14+ in `main()`, query active Hz, debug-only FPS/Hz overlay. Verify Windows/Linux follow the monitor. |
| **UI-A5** | [#175](https://github.com/QueryaHub/Querya-Desktop/issues/175) | `accessibility`, `settings` | **Reduced motion** — honor OS "reduce motion"; **Preferences → Appearance → Motion** (Full / Reduced / Off). |
| **UI-A6** | [#176](https://github.com/QueryaHub/Querya-Desktop/issues/176) | `docs`, `performance` | **Measurement & docs** — DevTools budget checklist (8.3 ms @120 Hz), per-OS Hz table, update design doc with measured results. |

## Suggested PR order

1. UI-A1 — motion tokens core (+ tests)
2. UI-A2 — adopt tokens across widgets
3. UI-A3 — smoother transitions (parallel with A4)
4. UI-A4 — high-refresh-rate enablement + debug overlay
5. UI-A5 — reduced-motion + Preferences toggle
6. UI-A6 — measurement, perf-baseline update, close milestone

## Out of scope for 0.4.4

- **Extensions sidebar and marketplace Explore UI** — deferred to **0.4.5+** (`ExtensionManifest` stub and `ThemeRemoteInstallService` from 0.4.3 remain the foundation); see [market-tech.md](market-tech.md).
- Non-theme extension types (drivers, SQL snippets).
- Mobile (iOS/Android) high-Hz setup — documented for the future in [motion-and-high-refresh.md §3](motion-and-high-refresh.md) but no `ios/`/`android/` targets exist yet.
