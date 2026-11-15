<script setup lang="ts">
import { computed, onUnmounted, ref } from "vue";
import { storeToRefs } from "pinia";
import { useShellStore } from "../stores/shell";
import { useConnectionsStore } from "../stores/connections";
import { useShellNavStore } from "../stores/shellNav";
import { useObjectTreeStore } from "../stores/objectTree";
import { useQueryaMotion } from "../motion";
import SplitHandle from "./SplitHandle.vue";
import QueryaContextMenu, { type CtxItem } from "./QueryaContextMenu.vue";

const emit = defineEmits<{
  newConnection: [];
  newFolder: [];
}>();

const shell = useShellStore();
const connections = useConnectionsStore();
const nav = useShellNavStore();
const tree = useObjectTreeStore();
const { items } = storeToRefs(connections);
const { selectedConnectionId, expandedConnectionIds, selectedObject } =
  storeToRefs(nav);
const { objects, filter: objectFilter, loading, error } = storeToRefs(tree);
const motion = useQueryaMotion();
const filter = ref("");
const dragging = ref(false);
const ctx = ref({ open: false, x: 0, y: 0 });

const ctxItems: CtxItem[] = [
  {
    id: "create",
    label: "Create",
    children: [
      { id: "new-connection", label: "New Connection" },
      { id: "new-folder", label: "New Folder" },
    ],
  },
];

const filteredConnections = computed(() => {
  const q = filter.value.trim().toLowerCase();
  if (!q) return items.value;
  return items.value.filter(
    (c) =>
      c.name.toLowerCase().includes(q) || c.path.toLowerCase().includes(q),
  );
});

const filteredObjects = computed(() => {
  const q = objectFilter.value.trim().toLowerCase();
  if (!q) return objects.value;
  return objects.value.filter((o) => o.name.toLowerCase().includes(q));
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
    if (shell.sidebarWidth < 100) shell.setSidebarOpen(false);
    window.removeEventListener("pointermove", onMove);
    window.removeEventListener("pointerup", onUp);
  };
  window.addEventListener("pointermove", onMove);
  window.addEventListener("pointerup", onUp);
}

function onConnClick(id: string) {
  connections.select(id);
}

function onConnExpand(id: string, e: MouseEvent) {
  e.stopPropagation();
  nav.toggleExpanded(id);
  connections.select(id);
}

function onObjectClick(name: string, kind: "table" | "view") {
  const id = selectedConnectionId.value;
  if (!id) return;
  nav.selectObject({ connectionId: id, name, kind });
}

function onObjectChevron(name: string, e: MouseEvent) {
  e.stopPropagation();
  void tree.toggleColumns(name);
}

function onPanelContext(e: MouseEvent) {
  // Only empty fill / panel chrome — not rows (they get their own menus later).
  const t = e.target as HTMLElement | null;
  if (t?.closest(".conn-row, .node-row, .cols, input, button")) return;
  e.preventDefault();
  ctx.value = { open: true, x: e.clientX, y: e.clientY };
}

function onCtxSelect(id: string) {
  if (id === "new-connection") emit("newConnection");
  else if (id === "new-folder") emit("newFolder");
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
    <div class="inner" @contextmenu="onPanelContext">
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
        <p v-if="!filteredConnections.length" class="empty-title">
          {{ filter ? `No connections match "${filter}"` : "No connections yet" }}
        </p>

        <ul
          v-else
          class="list"
          data-testid="connections-list"
        >
          <li
            v-for="c in filteredConnections"
            :key="c.id"
            class="conn"
            :class="{
              active: c.id === selectedConnectionId && !selectedObject,
              expanded: expandedConnectionIds.includes(c.id),
            }"
          >
            <div class="conn-row">
              <button
                type="button"
                class="chev"
                :aria-expanded="expandedConnectionIds.includes(c.id)"
                :aria-label="`Expand ${c.name}`"
                @click="onConnExpand(c.id, $event)"
              >
                {{ expandedConnectionIds.includes(c.id) ? "▾" : "▸" }}
              </button>
              <button
                type="button"
                class="conn-main"
                @click="onConnClick(c.id)"
              >
                <span class="conn-name">{{ c.name }}</span>
                <span class="conn-meta">
                  {{ c.driver }}<template v-if="c.mock"> · demo</template>
                </span>
              </button>
              <button
                type="button"
                class="conn-x"
                :aria-label="`Remove ${c.name}`"
                @click.stop="connections.disconnect(c.id)"
              >
                ×
              </button>
            </div>

            <div
              v-if="expandedConnectionIds.includes(c.id) && c.id === selectedConnectionId"
              class="tree"
              data-testid="sqlite-object-tree"
            >
              <div class="tree-header">
                <span class="tree-label">OBJECTS</span>
                <button
                  type="button"
                  class="refresh"
                  aria-label="Refresh"
                  @click="tree.refresh()"
                >
                  ↻
                </button>
              </div>
              <input
                v-model="objectFilter"
                class="filter"
                type="search"
                placeholder="Filter tables…"
                aria-label="Filter tables"
              />
              <p v-if="loading" class="hint">Loading…</p>
              <p v-else-if="error" class="hint err">{{ error }}</p>
              <ul v-else class="nodes">
                <li v-for="obj in filteredObjects" :key="obj.name" class="node">
                  <div
                    class="node-row"
                    :class="{
                      selected:
                        selectedObject?.name === obj.name &&
                        selectedObject?.connectionId === c.id,
                    }"
                  >
                    <button
                      type="button"
                      class="chev sm"
                      @click="onObjectChevron(obj.name, $event)"
                    >
                      {{ obj.expanded ? "▾" : "▸" }}
                    </button>
                    <button
                      type="button"
                      class="node-main"
                      @click="onObjectClick(obj.name, obj.kind)"
                    >
                      <span class="name">{{ obj.name }}</span>
                      <span class="kind">{{ obj.kind }}</span>
                    </button>
                  </div>
                  <ul v-if="obj.expanded" class="cols">
                    <li v-if="obj.loadingColumns" class="col muted">Loading…</li>
                    <li v-else-if="obj.error" class="col err">{{ obj.error }}</li>
                    <li
                      v-for="col in obj.columns ?? []"
                      :key="col.name"
                      class="col"
                    >
                      <span>
                        {{ col.name }}
                        <span v-if="col.is_primary_key" class="pk">PK</span>
                      </span>
                      <span class="type">{{ col.data_type || "—" }}</span>
                    </li>
                  </ul>
                </li>
              </ul>
            </div>
          </li>
        </ul>
      </div>
    </div>
    <SplitHandle v-if="shell.sidebarOpen" @pointerdown="onResizeStart" />
    <QueryaContextMenu
      :open="ctx.open"
      :x="ctx.x"
      :y="ctx.y"
      :items="ctxItems"
      @close="ctx.open = false"
      @select="onCtxSelect"
    />
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
  position: relative;
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

.servers-label,
.tree-label {
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
  padding: 4px 8px 16px;
  overflow: auto;
}

.empty-title {
  margin: 12px 4px 0;
  font-size: 13px;
  font-weight: 500;
  color: var(--q-muted-foreground);
}

.hint {
  margin: 6px 4px 0;
  font-size: 12px;
  color: var(--q-muted-foreground);
  line-height: 1.4;
}

.hint.err,
.col.err {
  color: var(--q-danger, #c44);
}

.list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.conn-row {
  display: flex;
  align-items: center;
  gap: 2px;
  border-radius: var(--q-radius-control);
}

.conn.active > .conn-row {
  background: color-mix(in srgb, var(--q-primary) 16%, transparent);
}

.chev {
  appearance: none;
  border: 0;
  background: transparent;
  width: 1.25rem;
  height: 1.5rem;
  color: var(--q-muted-foreground);
  cursor: pointer;
  font-size: 10px;
  flex-shrink: 0;
}

.chev.sm {
  width: 1rem;
}

.conn-main,
.node-main {
  appearance: none;
  border: 0;
  background: transparent;
  flex: 1;
  min-width: 0;
  text-align: left;
  padding: 6px 6px;
  cursor: pointer;
  color: var(--q-foreground);
  font: inherit;
  font-size: 12px;
  border-radius: var(--q-radius-control);
}

.conn-main:hover,
.node-main:hover {
  background: var(--q-accent);
}

.conn-name,
.name {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 500;
}

.conn-meta,
.kind,
.type {
  display: block;
  font-size: 10px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.conn-x,
.refresh {
  appearance: none;
  border: 0;
  background: transparent;
  width: 1.5rem;
  height: 1.5rem;
  border-radius: var(--q-radius-sm);
  color: var(--q-muted-foreground);
  cursor: pointer;
}

.conn-x:hover,
.refresh:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.tree {
  margin: 2px 0 8px 6px;
  padding: 6px 0 4px 6px;
  border-left: 1px solid
    color-mix(in srgb, var(--q-border) 55%, transparent);
}

.tree-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 4px;
}

.nodes,
.cols {
  list-style: none;
  margin: 6px 0 0;
  padding: 0;
}

.node-row {
  display: flex;
  align-items: center;
  border-radius: var(--q-radius-control);
}

.node-row.selected {
  background: color-mix(in srgb, var(--q-primary) 14%, transparent);
}

.cols {
  padding: 0 0 4px 1rem;
}

.col {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  padding: 2px 6px;
  font-size: 11px;
}

.col.muted {
  color: var(--q-muted-foreground);
}

.pk {
  margin-left: 4px;
  font-size: 9px;
  font-weight: 700;
  color: var(--q-primary);
  font-family: var(--q-font-mono);
}

</style>
