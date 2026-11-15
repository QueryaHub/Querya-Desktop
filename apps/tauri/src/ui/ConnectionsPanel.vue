<script setup lang="ts">
import { computed, onUnmounted, ref } from "vue";
import { useShellStore } from "../stores/shell";
import { useQueryaMotion } from "../motion";
import SplitHandle from "./SplitHandle.vue";

const emit = defineEmits<{
  openSqlite: [];
  newConnection: [];
}>();

const shell = useShellStore();
const motion = useQueryaMotion();
const filter = ref("");
const dragging = ref(false);

const panelStyle = computed(() => ({
  width: shell.sidebarOpen ? `${shell.sidebarWidth}px` : "0px",
  transitionProperty: dragging.value ? "none" : "width",
  transitionDuration: `${motion.duration("sidebarCubic")}ms`,
  transitionTimingFunction: motion.easing("standard"),
}));

function onResizeStart(e: PointerEvent) {
  if (!shell.sidebarOpen) return;
  e.preventDefault();
  dragging.value = true;
  const startX = e.clientX;
  const startW = shell.sidebarWidth;

  const onMove = (ev: PointerEvent) => {
    shell.setSidebarWidth(startW + (ev.clientX - startX));
  };
  const onUp = () => {
    dragging.value = false;
    // Flutter collapse threshold: flick under ~100px closes.
    if (shell.sidebarWidth < 100) shell.setSidebarOpen(false);
    window.removeEventListener("pointermove", onMove);
    window.removeEventListener("pointerup", onUp);
  };
  window.addEventListener("pointermove", onMove);
  window.addEventListener("pointerup", onUp);
}

onUnmounted(() => {
  dragging.value = false;
});
</script>

<template>
  <aside
    class="connections"
    data-testid="connections-panel"
    :class="{ open: shell.sidebarOpen, dragging }"
    :style="panelStyle"
    :aria-hidden="!shell.sidebarOpen"
  >
    <div class="inner">
      <div class="servers-header" data-testid="connections-servers-header">
        <span class="servers-label">SERVERS</span>
        <span class="count">0</span>
      </div>
      <div class="filter-row">
        <input
          v-model="filter"
          class="filter"
          type="search"
          placeholder="Filter connections…"
          aria-label="Filter connections"
          data-testid="connections-filter"
        />
      </div>
      <div class="body">
        <p class="empty-title">No connections yet</p>
        <p class="empty-hint">
          Open a SQLite file or add a server — drivers land with the vertical
          slice.
        </p>
        <div class="actions">
          <button
            type="button"
            class="btn primary"
            data-testid="connections-open-sqlite"
            @click="emit('openSqlite')"
          >
            Open SQLite…
          </button>
          <button
            type="button"
            class="btn"
            data-testid="connections-new"
            @click="emit('newConnection')"
          >
            New connection
          </button>
        </div>
      </div>
    </div>
    <SplitHandle v-if="shell.sidebarOpen" @pointerdown="onResizeStart" />
  </aside>
</template>

<style scoped>
.connections {
  position: relative;
  flex: 0 0 auto;
  height: 100%;
  min-width: 0;
  overflow: hidden;
  display: flex;
  flex-direction: row;
}

.inner {
  flex: 1;
  min-width: var(--q-sidebar-min);
  height: 100%;
  display: flex;
  flex-direction: column;
  background: var(--q-sidebar-bg);
  border-right: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
}

.servers-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 12px 6px;
}

.servers-label {
  font-family: var(--q-font-mono);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.85px;
  color: var(--q-muted-foreground);
}

.count {
  font-size: 11px;
  color: var(--q-muted-foreground);
  background: var(--q-accent);
  border-radius: 999px;
  padding: 0 6px;
  line-height: 18px;
}

.filter-row {
  padding: 0 10px 8px;
}

.filter {
  width: 100%;
  height: var(--q-control-h-sm);
  border: 1px solid var(--q-border);
  border-radius: var(--q-radius-control);
  background: var(--q-surface);
  color: var(--q-foreground);
  padding: 0 8px;
  font: inherit;
  font-size: 12px;
}

.filter:focus {
  outline: 2px solid color-mix(in srgb, var(--q-primary) 45%, transparent);
  outline-offset: 0;
}

.body {
  flex: 1;
  padding: 16px 12px;
  overflow: auto;
}

.empty-title {
  margin: 0;
  font-size: 13px;
  font-weight: 600;
  color: var(--q-foreground);
}

.empty-hint {
  margin: 6px 0 0;
  font-size: 12px;
  color: var(--q-muted-foreground);
  line-height: 1.4;
}

.actions {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-top: 14px;
}

.btn {
  appearance: none;
  height: var(--q-control-h-sm);
  border: 1px solid var(--q-border);
  border-radius: var(--q-radius-control);
  background: var(--q-surface);
  color: var(--q-foreground);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
  padding: 0 8px;
}

.btn:hover {
  background: var(--q-accent);
}

.btn.primary {
  background: var(--q-primary);
  border-color: transparent;
  color: var(--q-primary-foreground);
}

.btn.primary:hover {
  filter: brightness(1.05);
}
</style>
