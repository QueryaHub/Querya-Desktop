import { defineStore } from "pinia";
import { ref } from "vue";

const SIDEBAR_KEY = "querya.sidebar.width";
const SIDEBAR_OPEN_KEY = "querya.sidebar.open";
const MIN_WIDTH = 180;
const MAX_WIDTH = 420;
const DEFAULT_WIDTH = 240;

function readWidth(): number {
  const raw = Number(localStorage.getItem(SIDEBAR_KEY));
  if (Number.isFinite(raw) && raw >= MIN_WIDTH && raw <= MAX_WIDTH) return raw;
  return DEFAULT_WIDTH;
}

function readOpen(): boolean {
  const raw = localStorage.getItem(SIDEBAR_OPEN_KEY);
  if (raw === null) return true;
  return raw !== "0";
}

/** Shell chrome store — sidebar / ready flags for later connection tree. */
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
    const next = Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, Math.round(width)));
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
    minSidebarWidth: MIN_WIDTH,
    maxSidebarWidth: MAX_WIDTH,
  };
});
