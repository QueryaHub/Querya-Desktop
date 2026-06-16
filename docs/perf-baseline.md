# Flutter performance baseline (DevTools)

Use this checklist once per milestone so timeline comparisons stay meaningful. Run a **profile** or **release** build, not debug.

1. **Open DevTools → Performance** and start recording.
2. **Modal**: open any screen that uses `showAppDialog`; stop recording; note frame build/raster time around the transition.
3. **Connections tree**: expand/collapse a folder and a DB branch; note jank spikes.
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
7. **Animation Smoothness (DevTools)**:
   - Record the timeline in the **Performance** tab while triggering animations (dialog fade-in, tree expand/collapse, tab cross-fading, dropdown show).
   - Ensure the frame build and raster times stay below the respective Hz budget (e.g., < 8.3 ms on a 120 Hz monitor).
8. **Reduced Motion**:
   - Turn on "Reduce Motion" in your OS settings or select **Preferences → Appearance → Motion → Off** (or **Reduced** for 50% speed).
   - Verify that transitions complete instantly (**0 ms** for Off) or are appropriately shortened.
