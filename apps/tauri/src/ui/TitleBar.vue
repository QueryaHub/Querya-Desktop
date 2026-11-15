<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  detectPlatformFromUa,
  resolvePlatform,
  usesNativeTrafficLights,
  windowControlsSide,
  type QueryaPlatform,
} from "./platform";
import { useQueryaMotion } from "../motion";
import { useShellStore } from "../stores/shell";
import TitleBarMenus from "./TitleBarMenus.vue";
import { QueryaIcon } from "./icons";

const props = withDefaults(
  defineProps<{
    title?: string;
  }>(),
  { title: "Querya" },
);

const emit = defineEmits<{
  openSqlite: [];
  openPreferences: [];
  openPalette: [];
  openQuickSwitcher: [];
  openTour: [];
  openAbout: [];
  checkUpdates: [];
}>();

const motion = useQueryaMotion();
const shell = useShellStore();
const platform = ref<QueryaPlatform>(detectPlatformFromUa());
const maximized = ref(false);

/** macOS: left (native). Win/Linux: right caption buttons. */
const controlsSide = computed(() => windowControlsSide(platform.value));
const nativeTrafficLights = computed(() =>
  usesNativeTrafficLights(platform.value),
);

const barStyle = computed(() => ({
  transitionDuration: `${motion.duration("fast")}ms`,
  transitionTimingFunction: motion.easing("standard"),
}));

function isChromeInteractive(target: EventTarget | null): boolean {
  return Boolean(
    (target as HTMLElement | null)?.closest("button, a, input, [data-no-drag]"),
  );
}

async function refreshMaximized() {
  try {
    maximized.value = await getCurrentWindow().isMaximized();
  } catch {
    maximized.value = false;
  }
}

async function onMinimize() {
  await getCurrentWindow().minimize();
}

async function onToggleMaximize() {
  await getCurrentWindow().toggleMaximize();
  await refreshMaximized();
}

async function onClose() {
  await getCurrentWindow().close();
}

async function onDrag(e: MouseEvent) {
  if (e.button !== 0 || isChromeInteractive(e.target)) return;
  try {
    await getCurrentWindow().startDragging();
  } catch {
    // Permissions / non-Tauri preview — ignore.
  }
}

function onDblClick(e: MouseEvent) {
  if (isChromeInteractive(e.target)) return;
  void onToggleMaximize();
}

let unlistenResize: (() => void) | undefined;

onMounted(async () => {
  platform.value = await resolvePlatform();
  await refreshMaximized();
  try {
    unlistenResize = await getCurrentWindow().onResized(() => {
      void refreshMaximized();
    });
  } catch {
    // non-Tauri
  }
});

onUnmounted(() => {
  unlistenResize?.();
});
</script>

<template>
  <header
    class="titlebar q-glass"
    data-testid="title-bar"
    :data-platform="platform"
    :data-controls="controlsSide"
    :data-native-traffic="String(nativeTrafficLights)"
    :style="barStyle"
    @mousedown="onDrag"
    @dblclick="onDblClick"
  >
    <!-- Three regions keep Win/Linux caption buttons pinned right. -->
    <div class="region region--start" data-no-drag>
      <!-- macOS Overlay: reserve inset so sidebar/brand clear system lights. -->
      <span
        v-if="nativeTrafficLights"
        class="mac-inset"
        aria-hidden="true"
      />
      <button
        type="button"
        class="sidebar-toggle"
        data-testid="sidebar-toggle"
        :aria-pressed="shell.sidebarOpen"
        :aria-label="shell.sidebarOpen ? 'Hide sidebar' : 'Show sidebar'"
        @click="shell.toggleSidebar()"
      >
        <QueryaIcon name="sidebar" :size="16" />
      </button>
      <div class="brand" data-tauri-drag-region>
        <span class="mark" aria-hidden="true" />
        <span class="title">{{ props.title }}</span>
      </div>
      <TitleBarMenus
        @open-sqlite="emit('openSqlite')"
        @open-preferences="emit('openPreferences')"
        @open-palette="emit('openPalette')"
        @open-quick-switcher="emit('openQuickSwitcher')"
        @toggle-sidebar="shell.toggleSidebar()"
        @open-tour="emit('openTour')"
        @open-about="emit('openAbout')"
        @check-updates="emit('checkUpdates')"
      />
    </div>

    <div class="region region--center" data-tauri-drag-region />

    <div class="region region--end" data-no-drag>
      <div v-if="!nativeTrafficLights" class="controls controls--caption">
        <button
          type="button"
          class="caption minimize"
          aria-label="Minimize"
          @click="onMinimize"
        >
          <svg class="glyph" viewBox="0 0 10 10" width="10" height="10" aria-hidden="true">
            <path d="M1 5h8" />
          </svg>
        </button>
        <button
          type="button"
          class="caption maximize"
          :aria-label="maximized ? 'Restore' : 'Maximize'"
          @click="onToggleMaximize"
        >
          <!-- Restore: overlapping squares (Win 10/11). Maximize: single square. -->
          <svg
            v-if="maximized"
            class="glyph glyph--join"
            viewBox="0 0 10 10"
            width="10"
            height="10"
            aria-hidden="true"
          >
            <path d="M3 2.5h4.5V7M2.5 3.5H7v4.5H2.5z" />
          </svg>
          <svg
            v-else
            class="glyph"
            viewBox="0 0 10 10"
            width="10"
            height="10"
            aria-hidden="true"
          >
            <rect x="1.5" y="1.5" width="7" height="7" />
          </svg>
        </button>
        <button
          type="button"
          class="caption close"
          aria-label="Close"
          @click="onClose"
        >
          <svg
            class="glyph glyph--close"
            viewBox="0 0 10 10"
            width="10"
            height="10"
            aria-hidden="true"
          >
            <path d="M2 2l6 6M8 2l-6 6" />
          </svg>
        </button>
      </div>
      <!-- Balance the macOS traffic-light inset so the drag column stays even. -->
      <span v-else class="mac-inset" aria-hidden="true" />
    </div>
  </header>
</template>

<style scoped>
.titlebar {
  display: grid;
  grid-template-columns: minmax(7rem, 1fr) auto minmax(7rem, 1fr);
  align-items: center;
  height: var(--q-titlebar-h);
  min-height: var(--q-titlebar-h);
  padding: 0 var(--q-space-1);
  border-radius: 0;
  border-left: 0;
  border-right: 0;
  border-top: 0;
  user-select: none;
  transition-property: background-color, border-color, backdrop-filter;
  z-index: 20;
}

.region {
  display: flex;
  align-items: center;
  min-width: 0;
  height: 100%;
}

.region--start {
  justify-content: flex-start;
  gap: 6px;
  padding-left: var(--q-space-2);
  overflow: visible;
}

.region--center {
  justify-content: center;
}

.region--end {
  justify-content: flex-end;
  padding-right: 0;
}

.sidebar-toggle {
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  width: 1.75rem;
  height: 1.75rem;
  border-radius: var(--q-radius-sm);
  cursor: pointer;
  font-size: 0.9rem;
  line-height: 1;
  flex: 0 0 auto;
}

.sidebar-toggle:hover,
.sidebar-toggle[aria-pressed="true"] {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.brand {
  display: inline-flex;
  align-items: center;
  gap: var(--q-space-2);
  min-width: 0;
  padding: 0 4px 0 2px;
  flex: 0 0 auto;
}

.mark {
  width: 0.65rem;
  height: 0.65rem;
  border-radius: 999px;
  background: var(--q-primary);
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--q-primary) 25%, transparent);
}

.title {
  font-size: var(--q-text-sm);
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--q-foreground);
}

.controls {
  display: inline-flex;
  align-items: center;
  flex: 0 0 auto;
}

/* Reserved width for system traffic lights (Overlay titlebar on macOS).
   Native lights use window coords; counter-scale so UI zoom does not shrink the gap. */
.mac-inset {
  display: inline-block;
  width: calc(var(--q-mac-traffic-inset) / var(--q-ui-scale, 1));
  height: 1px;
  flex: 0 0 auto;
  pointer-events: none;
}

/* Windows / Linux — Fluent-style caption buttons (min / max / close). */
.controls--caption {
  gap: 0;
  height: 100%;
}

.caption {
  appearance: none;
  width: 46px;
  height: 100%;
  min-height: 32px;
  border: 0;
  border-radius: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  cursor: default;
  display: grid;
  place-items: center;
}

.caption:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.caption.close:hover {
  background: #e81123;
  color: #ffffff;
}

.glyph {
  display: block;
  fill: none;
  stroke: currentColor;
  stroke-width: 1;
  stroke-linecap: round;
}

.glyph--join {
  stroke-linejoin: round;
}

.glyph--close {
  stroke-width: 1.1;
}

/* macOS Overlay: content starts after the system lights. */
.titlebar[data-native-traffic="true"] .region--start {
  padding-left: 0;
}
</style>
