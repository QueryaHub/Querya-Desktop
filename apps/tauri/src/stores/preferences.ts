import { defineStore } from "pinia";
import { reactive, watch } from "vue";

const STORAGE_KEY = "querya.preferences.v1";

export type PrefsState = {
  checkUpdatesOnStartup: boolean;
  updateChannel: "stable" | "dev";
  confirmDestructive: boolean;
  editorFontSize: number;
  pgTimeoutSec: number | null;
  mysqlTimeoutSec: number | null;
  sqliteTimeoutSec: number | null;
  historyMax: number;
  maxResultRows: number;
  mcpEnabled: boolean;
  extensionsSideload: boolean;
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
  extensionsSideload: true,
};

function load(): PrefsState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return { ...defaults };
    return { ...defaults, ...JSON.parse(raw) };
  } catch {
    return { ...defaults };
  }
}

/** App preferences — Flutter PreferencesDialog shape, localStorage for now. */
export const usePreferencesStore = defineStore("preferences", () => {
  const state = reactive<PrefsState>(load());

  watch(
    state,
    () => {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    },
    { deep: true },
  );

  function reset() {
    Object.assign(state, defaults);
  }

  return { state, reset };
});
