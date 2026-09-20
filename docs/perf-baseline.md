# Flutter performance baseline (DevTools)

Use this checklist once per milestone so timeline comparisons stay meaningful. Run a **profile** or **release** build, not debug.

1. **Open DevTools → Performance** and start recording.
2. **Modal**: open any screen that uses `showAppDialog`; stop recording; note frame build/raster time around the transition.
3. **Connections tree**: expand/collapse a folder and a DB branch; note jank spikes. For a full 120 Hz runbook see [Connections sidebar tree @ 120 Hz](#connections-sidebar-tree--120-hz-723--727) below.
4. **Heavy scroll**: PostgreSQL/MySQL table view or Mongo documents list with many rows; scroll quickly for 2–3 seconds.

Save a screenshot or export the timeline when filing regressions. After UI changes, repeat the same steps and compare peak frame times and rebuild counts (Widget rebuild stats in DevTools).

## Motion and High-Hz Verification (0.4.4+)

To verify that the motion system conforms to the budget and does not cause jank at higher refresh rates:

5. **Vsync & Frame Budget**: Confirm your monitor refresh rate. 
   - 60 Hz budget: **16.6 ms** per frame
   - 90 Hz budget: **11.1 ms** per frame
   - 120 Hz budget: **8.3 ms** per frame
   - 144 Hz budget: **6.9 ms** per frame
6. **Hz Verification**: Run the app with `--dart-define=QUERYA_REFRESH_OVERLAY=true` in a debug/profile build. The floating overlay must show the correct target Hz.
   - **Linux:** overlay is **query-only** (`RefreshRate.enable` is a no-op). Confirm the compositor/monitor is actually driving that Hz (Wayland/X11 settings); Querya cannot unlock a higher rate.
7. **Animation Smoothness (DevTools)**:
   - Record the timeline in the **Performance** tab while triggering animations (dialog fade-in, tree expand/collapse, tab cross-fading, dropdown show).
   - Ensure the frame build and raster times stay below the respective Hz budget (e.g., < 8.3 ms on a 120 Hz monitor).
8. **Reduced Motion**:
   - Turn on "Reduce Motion" in your OS settings or select **Preferences → Appearance → Motion → Off** (or **Reduced** for 50% speed).
   - Verify that transitions complete instantly (**0 ms** for Off) or are appropriately shortened.

## Fluid shell scenarios @ 120 Hz (0.4.11+ / #342)

Repeat on a **120 Hz** display (budget **≤ 8.3 ms** build+raster). Prefer profile/release.

9. **Empty ↔ connected**: open a connection from the empty hero, then disconnect back to empty — `QueryaSwitchingBody` morph; editor/workspace state should not remount-jank.
10. **Tab strip**: switch Server / SQL / History quickly — sliding pill should redirect without brick-wall jumps.
11. **Hero quick-start ↔ recent**: with and without recent connections — FadeSlide + stagger first paint only.
12. **Results modes**: idle → run (spinner) → grid; force an error — mode keys morph; scrolling the grid must not fade rows.
13. **Dialog / dropdown**: open/close `showAppDialog` and a `QueryaDropdown` — enter fade-slide, exit uses exit curve; Motion Off snaps.
14. **Theme cross-fade**: Preferences → enable Animate theme + Motion Full; switch dark/light — shadcn + `AnimatedQueryaTheme` lerp. Repeat with Motion Off (snap).
    **Cost note:** theme morph rebuilds app-wide InheritedTheme dependents every tick — keep **Animate theme** **off by default** (`ThemeController`); only enable for demos/profile. Never ship it default-on without a 120 Hz timeline.
15. **Split settle**: drag the connections sidebar handle and the SQL/results vertical split with a fling — mid-drag stays 1:1; release may soft-settle. Focus the handle — ring uses motion tokens (not mid-drag animation).

## Connections sidebar tree @ 120 Hz (#723 / #727)

Repeatable capture for the **native** connections tree (PG / MySQL / SQLite / Redis / Mongo / extension SDUI). Use this before and after tree perf work so regressions show up in DevTools timelines.

**Setup**

- **Profile or release** build (not debug).
- **120 Hz** display; frame budget **≤ 8.3 ms** build + raster combined (see § Motion and High-Hz).
- Optional: `--dart-define=QUERYA_REFRESH_OVERLAY=true` to confirm target Hz on screen.
- DevTools → **Performance** (+ **Rebuild stats** when checking selection fan-out).
- Test data: at least one PG connection with a **large** database (many tables in one schema); **3+ connections** expanded in the sidebar when scrolling.

**Scenarios** (record each separately; note peak frame time and any sustained jank)

| # | Action | What to watch |
|---|--------|----------------|
| 1 | **Cold expand PG** — connection → Databases → database → schema → **Tables** (large DB) | Expand/collapse spikes; avoid nested shrink-wrap layout storms; large table lists should virtualize (viewport-only builds). |
| 2 | **Outer sidebar scroll** with **3+ connections** expanded (mix drivers if possible) | Scroll the panel `CustomScrollView` for 2–3 s; nested inner scrollers fighting the outer list cause dropped frames. |
| 3 | **Tables filter** — expand Tables, type in the group filter quickly | Debounced filter should not rebuild the whole expanded tree; typing should stay responsive. |
| 4 | **Rapid leaf selection** — 10 consecutive table/view clicks in the same group | Only previous + newly selected rows should rebuild (selection slice builder); avoid full-tree InheritedWidget fan-out. |
| 5 | **Motion Full vs Off** — repeat scenario 1 with **Preferences → Appearance → Motion → Full**, then **Off** | Off should skip height morph on large expands; expand should feel instant without multi-frame `AnimatedSize` on big lists. |

**Filing results**

- Attach DevTools Performance screenshots or exported timelines to epic [#723](https://github.com/QueryaHub/Querya-Desktop/issues/723) or the relevant child PR.
- Label captures **baseline** vs **post-fix** (e.g. after #725 selection rebuilds, #724 shrinkWrap removal, #726 expand motion gate).
- **Pass:** scenarios 1–4 stay within the 120 Hz budget during the action (no sustained >8.3 ms frames); scenario 5 shows clearly lower animation cost with Motion Off.

**Related code** (when investigating regressions)

- `lib/features/connections/connections_panel.dart` — `lazyConnectionTreeList`, selection `ValueNotifier` / `_ConnectionsTreeSelectionBuilder`
- `lib/core/motion/querya_animated_expand.dart` — large-list expand morph gate
- `lib/core/sdui/sdui_tree_builder.dart` — reference flat virtualized tree for extensions

