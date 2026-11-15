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

function load(): PrefsState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return { ...defaults };
    const parsed = JSON.parse(raw) as Partial<PrefsState>;
    return { ...defaults, ...parsed };
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
