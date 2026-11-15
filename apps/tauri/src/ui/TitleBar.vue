<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { detectPlatform, type QueryaPlatform } from "./platform";
import { useQueryaMotion } from "../motion";
import { useShellStore } from "../stores/shell";

const props = withDefaults(
  defineProps<{
    title?: string;
  }>(),
  { title: "Querya" },
);

const motion = useQueryaMotion();
const shell = useShellStore();
const platform = ref<QueryaPlatform>(detectPlatform());
const maximized = ref(false);

const controlsOnLeft = computed(() => platform.value === "macos");

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
  // Only primary button; ignore interactive children.
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
  platform.value = detectPlatform();
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
    :style="barStyle"
    @mousedown="onDrag"
    @dblclick="onDblClick"
  >
    <div
      v-if="controlsOnLeft"
      class="controls controls--left"
      data-no-drag
    >
      <button
        type="button"
        class="win-btn close"
        aria-label="Close"
        @click="onClose"
      />
      <button
        type="button"
        class="win-btn minimize"
        aria-label="Minimize"
        @click="onMinimize"
      />
      <button
        type="button"
        class="win-btn maximize"
        :aria-label="maximized ? 'Restore' : 'Maximize'"
        @click="onToggleMaximize"
      />
    </div>

    <div class="brand-row">
      <button
        type="button"
        class="sidebar-toggle"
        data-no-drag
        data-testid="sidebar-toggle"
        :aria-pressed="shell.sidebarOpen"
        :aria-label="shell.sidebarOpen ? 'Hide sidebar' : 'Show sidebar'"
        @click="shell.toggleSidebar()"
      >
        ☰
      </button>
      <div class="brand" data-tauri-drag-region>
        <span class="mark" aria-hidden="true" />
        <span class="title">{{ props.title }}</span>
      </div>
    </div>

    <div
      v-if="!controlsOnLeft"
      class="controls controls--right"
      data-no-drag
    >
      <button
        type="button"
        class="win-btn minimize"
        aria-label="Minimize"
        @click="onMinimize"
      >
        <span class="glyph" aria-hidden="true">─</span>
      </button>
      <button
        type="button"
        class="win-btn maximize"
        :aria-label="maximized ? 'Restore' : 'Maximize'"
        @click="onToggleMaximize"
      >
        <span class="glyph" aria-hidden="true">{{ maximized ? "❐" : "□" }}</span>
      </button>
      <button
        type="button"
        class="win-btn close"
        aria-label="Close"
        @click="onClose"
      >
        <span class="glyph" aria-hidden="true">✕</span>
      </button>
    </div>
    <div v-else class="spacer" aria-hidden="true" />
  </header>
</template>

<style scoped>
.titlebar {
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  height: 40px;
  min-height: 40px;
  padding: 0 var(--q-space-2);
  border-radius: 0;
  border-left: 0;
  border-right: 0;
  border-top: 0;
  user-select: none;
  transition-property: background-color, border-color, backdrop-filter;
  z-index: 20;
}

.brand-row {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--q-space-2);
  min-width: 0;
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
}

.sidebar-toggle:hover,
.sidebar-toggle[aria-pressed="true"] {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.brand {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--q-space-2);
  min-width: 0;
  pointer-events: none;
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
  gap: 0.4rem;
  padding: 0 var(--q-space-1);
}

.controls--right {
  gap: 0;
}

.spacer {
  width: 68px;
}

/* macOS-style traffic lights */
.controls--left .win-btn {
  width: 12px;
  height: 12px;
  border-radius: 999px;
  border: 0;
  padding: 0;
  cursor: default;
  background: var(--q-accent);
}

.controls--left .win-btn.close {
  background: #ff5f57;
}
.controls--left .win-btn.minimize {
  background: #febc2e;
}
.controls--left .win-btn.maximize {
  background: #28c840;
}

.controls--left .win-btn:hover {
  filter: brightness(1.05);
}

/* Win/Linux rectangle buttons */
.controls--right .win-btn {
  appearance: none;
  width: 46px;
  height: 32px;
  border: 0;
  border-radius: var(--q-radius-sm);
  background: transparent;
  color: var(--q-muted-foreground);
  cursor: default;
  display: grid;
  place-items: center;
}

.controls--right .win-btn:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.controls--right .win-btn.close:hover {
  background: var(--q-destructive);
  color: var(--q-destructive-foreground);
}

.glyph {
  font-size: 11px;
  line-height: 1;
}
</style>
