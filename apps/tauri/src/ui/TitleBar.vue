<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  detectPlatformFromUa,
  resolvePlatform,
  windowControlsSide,
  type QueryaPlatform,
} from "./platform";
import { useQueryaMotion } from "../motion";
import { useShellStore } from "../stores/shell";
import TitleBarMenus from "./TitleBarMenus.vue";

const props = withDefaults(
  defineProps<{
    title?: string;
  }>(),
  { title: "Querya" },
);

const emit = defineEmits<{
  newConnection: [];
  newConnectionFromUrl: [];
  openSqlite: [];
  openPreferences: [];
  openTour: [];
  launchDemo: [];
}>();

const motion = useQueryaMotion();
const shell = useShellStore();
const platform = ref<QueryaPlatform>(detectPlatformFromUa());
const maximized = ref(false);

/** macOS: left traffic lights. Win/Linux: right caption buttons. */
const controlsSide = computed(() => windowControlsSide(platform.value));
const controlsOnLeft = computed(() => controlsSide.value === "left");

const barStyle = computed(() => ({
  transitionDuration: `${motion.duration("fast")}ms`,
  transitionTimingFunction: motion.easing("standard"),
}));

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
  if (e.button !== 0) return;
  const target = e.target as HTMLElement | null;
  if (target?.closest("button, a, input, [data-no-drag]")) return;
  try {
    await getCurrentWindow().startDragging();
  } catch {
    // Permissions / non-Tauri preview — ignore.
  }
}

function onDblClick(e: MouseEvent) {
  const target = e.target as HTMLElement | null;
  if (target?.closest("button, a, input, [data-no-drag]")) return;
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
    :style="barStyle"
    @mousedown="onDrag"
    @dblclick="onDblClick"
  >
    <!-- Always three regions so Win/Linux keep controls pinned right. -->
    <div class="region region--start" data-no-drag>
      <div v-if="controlsOnLeft" class="controls controls--traffic">
        <button
          type="button"
          class="traffic close"
          aria-label="Close"
          @click="onClose"
        />
        <button
          type="button"
          class="traffic minimize"
          aria-label="Minimize"
          @click="onMinimize"
        />
        <button
          type="button"
          class="traffic maximize"
          :aria-label="maximized ? 'Restore' : 'Maximize'"
          @click="onToggleMaximize"
        />
      </div>
      <button
        type="button"
        class="sidebar-toggle"
        data-testid="sidebar-toggle"
        :aria-pressed="shell.sidebarOpen"
        :aria-label="shell.sidebarOpen ? 'Hide sidebar' : 'Show sidebar'"
        @click="shell.toggleSidebar()"
      >
        ▤
      </button>
      <div class="brand" data-tauri-drag-region>
        <span class="mark" aria-hidden="true" />
        <span class="title">{{ props.title }}</span>
      </div>
      <TitleBarMenus
        @new-connection="emit('newConnection')"
        @new-connection-from-url="emit('newConnectionFromUrl')"
        @open-sqlite="emit('openSqlite')"
        @open-preferences="emit('openPreferences')"
        @toggle-sidebar="shell.toggleSidebar()"
        @open-tour="emit('openTour')"
        @launch-demo="emit('launchDemo')"
      />
    </div>

    <div class="region region--center" data-tauri-drag-region />

    <div class="region region--end" data-no-drag>
      <div v-if="!controlsOnLeft" class="controls controls--caption">
        <button
          type="button"
          class="caption minimize"
          aria-label="Minimize"
          @click="onMinimize"
        >
          <span class="glyph" aria-hidden="true">─</span>
        </button>
        <button
          type="button"
          class="caption maximize"
          :aria-label="maximized ? 'Restore' : 'Maximize'"
          @click="onToggleMaximize"
        >
          <span class="glyph" aria-hidden="true">{{
            maximized ? "❐" : "□"
          }}</span>
        </button>
        <button
          type="button"
          class="caption close"
          aria-label="Close"
          @click="onClose"
        >
          <span class="glyph" aria-hidden="true">✕</span>
        </button>
      </div>
      <!-- Balance macOS traffic-light width so the title stays centered. -->
      <div
        v-else
        class="mac-balance"
        aria-hidden="true"
      />
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

/* macOS traffic lights — close / minimize / maximize */
.controls--traffic {
  gap: 8px;
  padding: 0 4px 0 6px;
  min-width: 52px;
}

.traffic {
  width: 12px;
  height: 12px;
  border-radius: 999px;
  border: 0;
  padding: 0;
  cursor: default;
  background: var(--q-accent);
}

.traffic.close {
  background: #ff5f57;
}
.traffic.minimize {
  background: #febc2e;
}
.traffic.maximize {
  background: #28c840;
}

.traffic:hover {
  filter: brightness(1.06);
}

.mac-balance {
  /* traffic cluster (~52) + sidebar toggle (~28) + gaps ≈ start cluster */
  width: 5.5rem;
  height: 1px;
  pointer-events: none;
}

/* Windows / Linux caption buttons — min / max / close on the right */
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
  background: var(--q-destructive);
  color: var(--q-destructive-foreground);
}

.glyph {
  font-size: 11px;
  line-height: 1;
}

/* Extra inset on macOS so lights clear the rounded corner / notch feel */
.titlebar[data-controls="left"] .region--start {
  padding-left: 12px;
}
</style>
