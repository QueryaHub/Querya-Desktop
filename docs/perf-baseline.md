# Flutter performance baseline (DevTools)

Use this checklist once per milestone so timeline comparisons stay meaningful. Run a **profile** or **release** build, not debug.

1. **Open DevTools → Performance** and start recording.
2. **Modal**: open any screen that uses `showAppDialog`; stop recording; note frame build/raster time around the transition.
3. **Connections tree**: expand/collapse a folder and a DB branch; note jank spikes.
4. **Heavy scroll**: PostgreSQL/MySQL table view or Mongo documents list with many rows; scroll quickly for 2–3 seconds.

Save a screenshot or export the timeline when filing regressions. After UI changes, repeat the same steps and compare peak frame times and rebuild counts (Widget rebuild stats in DevTools).
