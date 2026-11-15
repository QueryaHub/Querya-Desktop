<script setup lang="ts">
import { computed, onUnmounted, ref } from "vue";
import { storeToRefs } from "pinia";
import { useShellStore } from "../stores/shell";
import { useConnectionsStore } from "../stores/connections";
import { useQueryaMotion } from "../motion";
import SplitHandle from "./SplitHandle.vue";
import SqliteObjectTree from "./SqliteObjectTree.vue";

const emit = defineEmits<{
  openSqlite: [];
  newConnection: [];
}>();

const shell = useShellStore();
const connections = useConnectionsStore();
const { items, activeId } = storeToRefs(connections);
const motion = useQueryaMotion();
const filter = ref("");
const dragging = ref(false);

const filtered = computed(() => {
  const q = filter.value.trim().toLowerCase();
  if (!q) return items.value;
  return items.value.filter(
    (c) =>
      c.name.toLowerCase().includes(q) || c.path.toLowerCase().includes(q),
  );
});

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
        <span class="count">{{ items.length }}</span>
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
        <ul v-if="filtered.length" class="list" data-testid="connections-list">
          <li
            v-for="c in filtered"
            :key="c.id"
            class="row"
            :class="{ active: c.id === activeId }"
          >
            <button
              type="button"
              class="row-main"
              @click="connections.select(c.id)"
            >
              <span class="row-name">{{ c.name }}</span>
              <span class="row-meta">sqlite</span>
            </button>
            <button
              type="button"
              class="row-x"
              :aria-label="`Disconnect ${c.name}`"
              @click="connections.disconnect(c.id)"
            >
              ×
            </button>
          </li>
        </ul>
        <template v-else>
          <p class="empty-title">No connections yet</p>
          <p class="empty-hint">
            Open a SQLite file to start the vertical slice.
          </p>
        </template>
        <SqliteObjectTree />
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

.list {
  list-style: none;
  margin: 0 0 12px;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.row {
  display: flex;
  align-items: center;
  gap: 2px;
  border-radius: var(--q-radius-control);
}

.row.active {
  background: color-mix(in srgb, var(--q-primary) 16%, transparent);
}

.row-main {
  appearance: none;
  border: 0;
  background: transparent;
  flex: 1;
  min-width: 0;
  text-align: left;
  padding: 6px 8px;
  cursor: pointer;
  color: var(--q-foreground);
  font: inherit;
  font-size: 12px;
  border-radius: var(--q-radius-control);
}

.row-main:hover {
  background: var(--q-accent);
}

.row-name {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 500;
}

.row-meta {
  display: block;
  font-size: 10px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.row-x {
  appearance: none;
  border: 0;
  background: transparent;
  width: 1.5rem;
  height: 1.5rem;
  border-radius: var(--q-radius-sm);
  color: var(--q-muted-foreground);
  cursor: pointer;
}

.row-x:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
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
