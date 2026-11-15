<script setup lang="ts">
import { computed, onUnmounted, ref } from "vue";
import { storeToRefs } from "pinia";
import { useShellStore } from "../stores/shell";
import { useConnectionsStore } from "../stores/connections";
import { useFoldersStore } from "../stores/folders";
import {
  isPgSchemaToolFolder,
  useShellNavStore,
} from "../stores/shellNav";
import { useObjectTreeStore, type TreeUiNode } from "../stores/objectTree";
import { useQueryaMotion } from "../motion";
import SplitHandle from "./SplitHandle.vue";
import QueryaContextMenu, { type CtxItem } from "./QueryaContextMenu.vue";
import SqlObjectTreeNodes from "./SqlObjectTreeNodes.vue";
import { QueryaIcon, QueryaDriverIcon } from "./icons";

const emit = defineEmits<{
  newConnection: [];
  newFolder: [];
}>();

const shell = useShellStore();
const connections = useConnectionsStore();
const foldersStore = useFoldersStore();
const nav = useShellNavStore();
const tree = useObjectTreeStore();
const { items } = storeToRefs(connections);
const { folders } = storeToRefs(foldersStore);
const { selectedConnectionId, selectedObject } = storeToRefs(nav);
const motion = useQueryaMotion();
const filter = ref("");
const dragging = ref(false);

type CtxTarget =
  | { type: "panel" }
  | { type: "folder"; folderId: string }
  | { type: "connection"; connectionId: string };

const ctx = ref<{ open: boolean; x: number; y: number; target: CtxTarget }>({
  open: false,
  x: 0,
  y: 0,
  target: { type: "panel" },
});

const filteredConnections = computed(() => {
  const q = filter.value.trim().toLowerCase();
  if (!q) return items.value;
  return items.value.filter((c) => {
    if (c.name.toLowerCase().includes(q)) return true;
    if (c.path?.toLowerCase().includes(q)) return true;
    if (c.host?.toLowerCase().includes(q)) return true;
    if (c.database?.toLowerCase().includes(q)) return true;
    return false;
  });
});

const rootConnections = computed(() =>
  filteredConnections.value.filter((c) => !c.folderId),
);

const folderRows = computed(() => {
  const q = filter.value.trim().toLowerCase();
  return folders.value
    .map((f) => {
      const children = filteredConnections.value.filter(
        (c) => c.folderId === f.id,
      );
      const nameHit = !q || f.name.toLowerCase().includes(q);
      if (!nameHit && !children.length) return null;
      return { folder: f, children, forceOpen: Boolean(q) && children.length > 0 };
    })
    .filter((row): row is NonNullable<typeof row> => row != null);
});

const ctxItems = computed<CtxItem[]>(() => {
  const t = ctx.value.target;
  if (t.type === "folder") {
    return [
      { id: "new-connection", label: "New Connection" },
      { id: "remove-folder", label: "Remove folder" },
    ];
  }
  if (t.type === "connection") {
    const moveKids: CtxItem[] = [
      { id: "move-root", label: "No folder" },
      ...folders.value.map((f) => ({
        id: `move:${f.id}`,
        label: f.name,
      })),
    ];
    return [
      nav.isExpanded(t.connectionId)
        ? { id: "collapse", label: "Collapse" }
        : { id: "expand", label: "Expand" },
      { id: "disconnect", label: "Disconnect" },
      { id: "remove", label: "Remove connection" },
      {
        id: "move",
        label: "Move to folder",
        children: moveKids,
      },
    ];
  }
  return [
    {
      id: "create",
      label: "Create",
      children: [
        { id: "new-connection", label: "New Connection" },
        { id: "new-folder", label: "New Folder" },
      ],
    },
  ];
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
  const willExpand = !nav.isExpanded(id);
  nav.toggleExpanded(id);
  if (willExpand) void tree.ensureLoaded(id);
}

function onFolderExpand(id: string, e: MouseEvent) {
  e.stopPropagation();
  foldersStore.toggleExpanded(id);
}

function onRelationClick(connectionId: string, node: TreeUiNode) {
  const selectable =
    node.kind === "table" ||
    node.kind === "view" ||
    node.kind === "materialized_view" ||
    node.kind === "function" ||
    node.kind === "sequence" ||
    node.kind === "index" ||
    node.kind === "trigger" ||
    node.kind === "type" ||
    isPgSchemaToolFolder(node);
  if (!selectable) return;
  connections.select(connectionId);
  nav.selectObject({
    connectionId,
    name: node.name,
    kind: node.kind as
      | "table"
      | "view"
      | "materialized_view"
      | "function"
      | "sequence"
      | "index"
      | "trigger"
      | "type"
      | "folder",
    objectId: node.id,
    schema: node.schema,
  });
}

function onNodeChevron(connectionId: string, node: TreeUiNode, e: MouseEvent) {
  e.stopPropagation();
  void tree.toggleExpand(connectionId, node.id);
}

function openCtx(e: MouseEvent, target: CtxTarget) {
  e.preventDefault();
  e.stopPropagation();
  ctx.value = { open: true, x: e.clientX, y: e.clientY, target };
}

function onPanelContext(e: MouseEvent) {
  const t = e.target as HTMLElement | null;
  if (t?.closest(".conn-row, .folder-row, .node-row, .cols, input, button"))
    return;
  openCtx(e, { type: "panel" });
}

function onCtxSelect(id: string) {
  const t = ctx.value.target;
  if (id === "new-connection") emit("newConnection");
  else if (id === "new-folder") emit("newFolder");
  else if (id === "remove-folder" && t.type === "folder") {
    connections.detachFolder(t.folderId);
    foldersStore.remove(t.folderId);
  } else if (id === "expand" && t.type === "connection") {
    nav.setExpanded(t.connectionId, true);
    void tree.ensureLoaded(t.connectionId);
  } else if (id === "collapse" && t.type === "connection") {
    nav.setExpanded(t.connectionId, false);
  } else if (id === "disconnect" && t.type === "connection") {
    void connections.disconnect(t.connectionId);
    nav.setExpanded(t.connectionId, false);
    tree.drop(t.connectionId);
  } else if (id === "remove" && t.type === "connection") {
    void connections.removeConnection(t.connectionId);
    tree.drop(t.connectionId);
  } else if (id === "move-root" && t.type === "connection") {
    connections.moveToFolder(t.connectionId, null);
  } else if (id.startsWith("move:") && t.type === "connection") {
    connections.moveToFolder(t.connectionId, id.slice(5));
  }
}

function treeState(connId: string) {
  return tree.stateOf(connId);
}

function filteredRootsFor(connId: string) {
  return tree.filteredRootsFor(connId);
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
        <p v-if="!filteredConnections.length && !folderRows.length" class="empty-title">
          {{ filter ? `No connections match "${filter}"` : "No connections yet" }}
        </p>

        <ul v-else class="list" data-testid="connections-list">
          <!-- Folders -->
          <li
            v-for="row in folderRows"
            :key="row.folder.id"
            class="folder"
            :class="{ expanded: row.folder.expanded || row.forceOpen }"
          >
            <div
              class="folder-row"
              @contextmenu="openCtx($event, { type: 'folder', folderId: row.folder.id })"
            >
              <button
                type="button"
                class="chev"
                :aria-expanded="row.folder.expanded || row.forceOpen"
                :aria-label="`Expand ${row.folder.name}`"
                @click="onFolderExpand(row.folder.id, $event)"
              >
                <QueryaIcon
                  :name="
                    row.folder.expanded || row.forceOpen
                      ? 'chevronDown'
                      : 'chevronRight'
                  "
                  :size="12"
                />
              </button>
              <QueryaIcon class="folder-ico" name="folder" :size="14" />
              <span class="folder-name">{{ row.folder.name }}</span>
              <span class="count-sm">{{ row.children.length }}</span>
            </div>

            <ul
              v-if="row.folder.expanded || row.forceOpen"
              class="folder-kids"
            >
              <li
                v-for="c in row.children"
                :key="c.id"
                class="conn"
                :class="{
                  active: c.id === selectedConnectionId && !selectedObject,
                  expanded: nav.isExpanded(c.id),
                }"
              >
                <div
                  class="conn-row"
                  @contextmenu="
                    openCtx($event, { type: 'connection', connectionId: c.id })
                  "
                >
                  <button
                    type="button"
                    class="chev"
                    :aria-expanded="nav.isExpanded(c.id)"
                    :aria-label="
                      nav.isExpanded(c.id)
                        ? `Collapse ${c.name}`
                        : `Expand ${c.name}`
                    "
                    @click="onConnExpand(c.id, $event)"
                  >
                    <QueryaIcon
                      :name="nav.isExpanded(c.id) ? 'chevronDown' : 'chevronRight'"
                      :size="12"
                    />
                  </button>
                  <button
                    type="button"
                    class="conn-main"
                    @click="onConnClick(c.id)"
                    @dblclick="onConnExpand(c.id, $event)"
                  >
                    <QueryaDriverIcon
                      class="glyph"
                      :driver="c.driver"
                      :mock="!!c.mock"
                      :size="14"
                    />
                    <span class="conn-name">{{ c.name }}</span>
                    <span class="conn-meta">
                      {{ c.driver
                      }}<template v-if="c.mock"> · demo</template>
                    </span>
                  </button>
                </div>

                <div
                  v-if="nav.isExpanded(c.id) && c.driver === 'redis'"
                  class="tree"
                  data-testid="redis-db-tree"
                >
                  <div class="tree-header">
                    <span class="tree-label">DATABASE</span>
                  </div>
                  <ul class="nodes">
                    <li class="redis-db">
                      db{{ c.database ?? "0" }}
                    </li>
                  </ul>
                </div>
                <div
                  v-else-if="nav.isExpanded(c.id)"
                  class="tree"
                  data-testid="sqlite-object-tree"
                >
                  <div class="tree-header">
                    <span class="tree-label">OBJECTS</span>
                    <button
                      type="button"
                      class="refresh"
                      aria-label="Refresh"
                      @click="tree.refresh(c.id)"
                    >
                      <QueryaIcon name="refresh" :size="12" />
                    </button>
                  </div>
                  <input
                    class="filter"
                    type="search"
                    placeholder="Filter objects…"
                    aria-label="Filter objects"
                    :value="treeState(c.id).filter"
                    @input="
                      tree.setFilter(
                        c.id,
                        ($event.target as HTMLInputElement).value,
                      )
                    "
                  />
                  <p v-if="treeState(c.id).loading" class="hint">Loading…</p>
                  <p v-else-if="treeState(c.id).error" class="hint err">
                    {{ treeState(c.id).error }}
                  </p>
                  <ul v-else class="nodes">
                    <SqlObjectTreeNodes
                      :nodes="filteredRootsFor(c.id)"
                      :connection-id="c.id"
                      :selected-object="selectedObject"
                      :depth="0"
                      @toggle="(n, e) => onNodeChevron(c.id, n, e)"
                      @select-relation="(n) => onRelationClick(c.id, n)"
                    />
                  </ul>
                </div>
              </li>
            </ul>
          </li>

          <!-- Root connections (no folder) -->
          <li
            v-for="c in rootConnections"
            :key="c.id"
            class="conn"
            :class="{
              active: c.id === selectedConnectionId && !selectedObject,
              expanded: nav.isExpanded(c.id),
            }"
          >
            <div
              class="conn-row"
              @contextmenu="
                openCtx($event, { type: 'connection', connectionId: c.id })
              "
            >
              <button
                type="button"
                class="chev"
                :aria-expanded="nav.isExpanded(c.id)"
                :aria-label="
                  nav.isExpanded(c.id)
                    ? `Collapse ${c.name}`
                    : `Expand ${c.name}`
                "
                @click="onConnExpand(c.id, $event)"
              >
                <QueryaIcon
                  :name="nav.isExpanded(c.id) ? 'chevronDown' : 'chevronRight'"
                  :size="12"
                />
              </button>
              <button
                type="button"
                class="conn-main"
                @click="onConnClick(c.id)"
                @dblclick="onConnExpand(c.id, $event)"
              >
                <QueryaDriverIcon
                  class="glyph"
                  :driver="c.driver"
                  :mock="!!c.mock"
                  :size="14"
                />
                <span class="conn-name">{{ c.name }}</span>
                <span class="conn-meta">
                  {{ c.driver }}<template v-if="c.mock"> · demo</template>
                </span>
              </button>
            </div>

            <div
              v-if="nav.isExpanded(c.id) && c.driver === 'redis'"
              class="tree"
              data-testid="redis-db-tree"
            >
              <div class="tree-header">
                <span class="tree-label">DATABASE</span>
              </div>
              <ul class="nodes">
                <li class="redis-db">
                  db{{ c.database ?? "0" }}
                </li>
              </ul>
            </div>
            <div
              v-else-if="nav.isExpanded(c.id)"
              class="tree"
              data-testid="sqlite-object-tree"
            >
              <div class="tree-header">
                <span class="tree-label">OBJECTS</span>
                <button
                  type="button"
                  class="refresh"
                  aria-label="Refresh"
                  @click="tree.refresh(c.id)"
                >
                  <QueryaIcon name="refresh" :size="12" />
                </button>
              </div>
              <input
                class="filter"
                type="search"
                placeholder="Filter objects…"
                aria-label="Filter objects"
                :value="treeState(c.id).filter"
                @input="
                  tree.setFilter(
                    c.id,
                    ($event.target as HTMLInputElement).value,
                  )
                "
              />
              <p v-if="treeState(c.id).loading" class="hint">Loading…</p>
              <p v-else-if="treeState(c.id).error" class="hint err">
                {{ treeState(c.id).error }}
              </p>
              <ul v-else class="nodes">
                <SqlObjectTreeNodes
                  :nodes="filteredRootsFor(c.id)"
                  :connection-id="c.id"
                  :selected-object="selectedObject"
                  :depth="0"
                  @toggle="(n, e) => onNodeChevron(c.id, n, e)"
                  @select-relation="(n) => onRelationClick(c.id, n)"
                />
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
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.06em;
  color: var(--q-muted-foreground);
}

.count,
.count-sm {
  font-size: 10px;
  color: var(--q-muted-foreground);
  font-variant-numeric: tabular-nums;
}

.filter-row {
  padding: 0 10px 8px;
}

.filter {
  width: 100%;
  height: 28px;
  border-radius: 6px;
  border: 1px solid color-mix(in srgb, var(--q-border) 70%, transparent);
  background: var(--q-surface);
  color: var(--q-foreground);
  padding: 0 8px;
  font: inherit;
  font-size: 12px;
}

.body {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 0 6px 12px;
}

.empty-title {
  margin: 16px 8px;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.list,
.folder-kids,
.nodes {
  list-style: none;
  margin: 0;
  padding: 0;
}

.folder-row,
.conn-row {
  display: flex;
  align-items: center;
  gap: 2px;
  border-radius: var(--q-radius-control);
  padding-right: 2px;
}

.folder-row:hover,
.conn.active > .conn-row {
  background: color-mix(in srgb, var(--q-primary) 10%, transparent);
}

.folder-ico {
  color: var(--q-muted-foreground);
}

.folder-name {
  flex: 1;
  font-size: 12px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.chev {
  width: 18px;
  height: 18px;
  flex: 0 0 18px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  cursor: pointer;
  padding: 0;
}

.conn-main {
  flex: 1;
  min-width: 0;
  display: grid;
  grid-template-columns: auto 1fr;
  grid-template-rows: auto auto;
  column-gap: 8px;
  row-gap: 1px;
  align-items: center;
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-foreground);
  font: inherit;
  text-align: left;
  padding: 5px 6px;
  border-radius: var(--q-radius-control);
  cursor: pointer;
}

.conn-main .glyph {
  grid-row: 1 / span 2;
  color: var(--q-muted-foreground);
}

.conn-main .conn-name {
  grid-column: 2;
  grid-row: 1;
}

.conn-main .conn-meta {
  grid-column: 2;
  grid-row: 2;
}

.conn-main:hover {
  background: var(--q-accent);
}

.conn-name {
  display: block;
  width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 500;
  font-size: 12px;
}

.conn-meta {
  display: block;
  font-size: 10px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

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

.refresh:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.folder-kids {
  margin: 0 0 4px 6px;
  padding-left: 4px;
  border-left: 1px solid color-mix(in srgb, var(--q-border) 45%, transparent);
}

.tree {
  margin: 2px 0 8px 6px;
  padding: 6px 0 4px 6px;
  border-left: 1px solid color-mix(in srgb, var(--q-border) 55%, transparent);
}

.tree-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 4px;
}

.tree .filter {
  margin-bottom: 4px;
}

.hint {
  margin: 6px 4px;
  font-size: 11px;
  color: var(--q-muted-foreground);
}

.hint.err {
  color: var(--q-destructive);
}

.nodes {
  margin: 4px 0 0;
}

.redis-db {
  list-style: none;
  padding: 4px 8px;
  font-size: 12px;
  font-family: var(--q-font-mono);
  color: var(--q-muted-foreground);
}
</style>
