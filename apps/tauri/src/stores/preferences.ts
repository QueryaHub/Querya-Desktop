import { defineStore } from "pinia";
import { reactive, watch } from "vue";

const STORAGE_KEY = "querya.preferences.v1";

export type PrefsState = {
  checkUpdatesOnStartup: boolean;
  updateChannel: "stable" | "dev";
  confirmDestructive: boolean;
  editorFontSize: number;
  /** null = no limit */
  pgTimeoutSec: number | null;
  mysqlTimeoutSec: number | null;
  sqliteTimeoutSec: number | null;
  historyMax: number;
  maxResultRows: number;
  mcpEnabled: boolean;
  /** Percent — default 100. Presets or 1% fine values (75–200). */
  uiScale: number;
  animateThemeChanges: boolean;
};

const defaults: PrefsState = {
  checkUpdatesOnStartup: true,
  updateChannel: "stable",
  confirmDestructive: true,
  editorFontSize: 13,
  pgTimeoutSec: 30,
  mysqlTimeoutSec: 30,
  sqliteTimeoutSec: 30,
  historyMax: 200,
  maxResultRows: 5000,
  mcpEnabled: false,
  uiScale: 100,
  animateThemeChanges: true,
};

const SCALE_PRESETS = [75, 85, 90, 100, 110, 125, 150, 175, 200] as const;

function snapToPreset(n: number): number {
  return SCALE_PRESETS.reduce((best, p) =>
    Math.abs(p - n) < Math.abs(best - n) ? p : best,
  );
}

/** Accept preset or integer 75–200 (Shift fine); otherwise snap to nearest preset. */
function normalizeUiScale(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return defaults.uiScale;
  if (Number.isInteger(n) && n >= 75 && n <= 200) return n;
  return snapToPreset(n);
}

function load(): PrefsState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return { ...defaults };
    const parsed = JSON.parse(raw) as Partial<PrefsState>;
    const merged = { ...defaults, ...parsed };
    merged.uiScale = normalizeUiScale(merged.uiScale);
    return merged;
  } catch {
    return { ...defaults };
  }
}

function applyUiScale(percent: number) {
  document.documentElement.style.setProperty(
    "--q-ui-scale",
    String(percent / 100),
  );
}

/** Flutter PreferencesDialog shape — localStorage until app settings land. */
export const usePreferencesStore = defineStore("preferences", () => {
  const state = reactive<PrefsState>(load());

  watch(
    state,
    () => {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
      applyUiScale(state.uiScale);
    },
    { deep: true, immediate: true },
  );

  function resetAppearance() {
    state.uiScale = defaults.uiScale;
    state.animateThemeChanges = defaults.animateThemeChanges;
  }

  function reset() {
    Object.assign(state, defaults);
  }

  return { state, reset, resetAppearance };
});
