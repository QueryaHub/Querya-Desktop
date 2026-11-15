<script setup lang="ts">
import {
  isPgSchemaToolFolder,
  type SelectedObject,
} from "../stores/shellNav";
import type { TreeUiNode } from "../stores/objectTree";

defineProps<{
  nodes: TreeUiNode[];
  connectionId: string;
  selectedObject: SelectedObject | null;
  depth: number;
}>();

const emit = defineEmits<{
  toggle: [node: TreeUiNode, e: MouseEvent];
  selectRelation: [node: TreeUiNode];
}>();

function kindGlyph(kind: TreeUiNode["kind"]): string {
  switch (kind) {
    case "schema":
      return "▣";
    case "folder":
      return "▸";
    case "view":
    case "materialized_view":
      return "◌";
    case "function":
    case "procedure":
      return "ƒ";
    case "sequence":
      return "#";
    case "index":
      return "⌘";
    case "trigger":
      return "⚡";
    case "type":
      return "T";
    case "column":
      return "·";
    default:
      return "▤";
  }
}

function isRelation(
  kind: TreeUiNode["kind"],
): kind is "table" | "view" | "materialized_view" {
  return kind === "table" || kind === "view" || kind === "materialized_view";
}

function isSelectable(node: TreeUiNode): boolean {
  if (isRelation(node.kind)) return true;
  if (
    node.kind === "function" ||
    node.kind === "sequence" ||
    node.kind === "index" ||
    node.kind === "trigger" ||
    node.kind === "type"
  ) {
    return true;
  }
  return isPgSchemaToolFolder(node);
}

function isSelected(
  node: TreeUiNode,
  connectionId: string,
  selected: SelectedObject | null,
): boolean {
  if (!selected || selected.connectionId !== connectionId) return false;
  if (selected.objectId) return selected.objectId === node.id;
  return (
    isRelation(node.kind) &&
    selected.name === node.name &&
    selected.kind === node.kind
  );
}
</script>

<template>
  <li
    v-for="node in nodes"
    :key="node.id"
    class="node"
    :style="{ '--depth': depth }"
  >
    <div
      class="node-row"
      :class="{
        selected: isSelected(node, connectionId, selectedObject),
        column: node.kind === 'column',
      }"
    >
      <button
        v-if="node.expandable"
        type="button"
        class="chev sm"
        :aria-expanded="node.expanded"
        :aria-label="`Expand ${node.name}`"
        @click="emit('toggle', node, $event)"
      >
        {{ node.expanded ? "▾" : "▸" }}
      </button>
      <span v-else class="chev-spacer" />
      <button
        type="button"
        class="node-main"
        :disabled="!isSelectable(node)"
        @click="isSelectable(node) && emit('selectRelation', node)"
      >
        <span class="glyph" aria-hidden="true">{{ kindGlyph(node.kind) }}</span>
        <span class="name">{{ node.name }}</span>
        <span class="kind">{{ node.kind }}</span>
      </button>
    </div>
    <ul v-if="node.expanded" class="kids">
      <li v-if="node.loading" class="col muted">Loading…</li>
      <li v-else-if="node.error" class="col err">{{ node.error }}</li>
      <SqlObjectTreeNodes
        v-else-if="node.children?.length"
        :nodes="node.children"
        :connection-id="connectionId"
        :selected-object="selectedObject"
        :depth="depth + 1"
        @toggle="(n, e) => emit('toggle', n, e)"
        @select-relation="(n) => emit('selectRelation', n)"
      />
      <li v-else-if="node.children" class="col muted">Empty</li>
    </ul>
  </li>
</template>

<style scoped>
.node {
  list-style: none;
}

.node-row {
  display: flex;
  align-items: center;
  gap: 2px;
  padding-left: calc(var(--depth, 0) * 10px);
  border-radius: 4px;
}

.node-row.selected {
  background: color-mix(in srgb, var(--q-primary) 14%, transparent);
}

.node-row.column .name {
  font-weight: 400;
}

.chev,
.chev-spacer {
  width: 18px;
  flex: 0 0 18px;
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  cursor: pointer;
  font-size: 10px;
  line-height: 1;
  padding: 0;
}

.chev-spacer {
  cursor: default;
}

.node-main {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 6px;
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-foreground);
  font: inherit;
  font-size: 12px;
  text-align: left;
  padding: 4px 6px;
  border-radius: 4px;
  cursor: pointer;
}

.node-main:disabled {
  cursor: default;
}

.node-main:not(:disabled):hover {
  background: var(--q-accent);
}

.glyph {
  width: 12px;
  text-align: center;
  color: var(--q-muted-foreground);
  font-size: 10px;
}

.name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 500;
}

.kind {
  flex: 0 0 auto;
  font-size: 10px;
  color: var(--q-muted-foreground);
  text-transform: uppercase;
}

.kids {
  list-style: none;
  margin: 0;
  padding: 0;
}

.col {
  padding: 2px 8px 2px calc(var(--depth, 0) * 10px + 28px);
  font-size: 11px;
}

.muted {
  color: var(--q-muted-foreground);
}

.err {
  color: var(--q-destructive);
}
</style>
