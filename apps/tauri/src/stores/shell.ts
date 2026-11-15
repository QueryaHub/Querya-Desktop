import { defineStore } from "pinia";
import { ref } from "vue";

/** Flutter MainContentSplit / AppSettings defaults. */
const SIDEBAR_KEY = "querya.sidebar.width";
const SIDEBAR_OPEN_KEY = "querya.sidebar.open";
export const SIDEBAR_MIN = 180;
export const SIDEBAR_MAX = 500;
export const SIDEBAR_DEFAULT = 260;

function readWidth(): number {
  const raw = Number(localStorage.getItem(SIDEBAR_KEY));
  if (Number.isFinite(raw) && raw >= SIDEBAR_MIN && raw <= SIDEBAR_MAX) {
    return raw;
  }
  return SIDEBAR_DEFAULT;
}

function readOpen(): boolean {
  const raw = localStorage.getItem(SIDEBAR_OPEN_KEY);
  if (raw === null) return true;
  return raw !== "0";
}

/** Shell chrome — Flutter MainScreen sidebar + ready flag. */
export const useShellStore = defineStore("shell", () => {
  const ready = ref(false);
  const sidebarOpen = ref(readOpen());
  const sidebarWidth = ref(readWidth());

  function markReady() {
    ready.value = true;
  }

  function setSidebarOpen(open: boolean) {
    sidebarOpen.value = open;
    localStorage.setItem(SIDEBAR_OPEN_KEY, open ? "1" : "0");
  }

  function toggleSidebar() {
    setSidebarOpen(!sidebarOpen.value);
  }

  function setSidebarWidth(width: number) {
    const next = Math.min(SIDEBAR_MAX, Math.max(SIDEBAR_MIN, Math.round(width)));
    sidebarWidth.value = next;
    localStorage.setItem(SIDEBAR_KEY, String(next));
  }

  return {
    ready,
    markReady,
    sidebarOpen,
    sidebarWidth,
    setSidebarOpen,
    toggleSidebar,
    setSidebarWidth,
    minSidebarWidth: SIDEBAR_MIN,
    maxSidebarWidth: SIDEBAR_MAX,
  };
});
