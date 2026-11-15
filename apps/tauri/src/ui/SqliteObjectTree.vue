<script setup lang="ts">
import { computed } from "vue";
import { storeToRefs } from "pinia";
import { useObjectTreeStore } from "../stores/objectTree";

const tree = useObjectTreeStore();
const { objects, loading, error, filter, connectionId } = storeToRefs(tree);

const filtered = computed(() => {
  const q = filter.value.trim().toLowerCase();
  if (!q) return objects.value;
  return objects.value.filter((o) => o.name.toLowerCase().includes(q));
});
</script>

<template>
  <section
    v-if="connectionId"
    class="tree"
    data-testid="sqlite-object-tree"
    aria-label="Database objects"
  >
    <div class="tree-header">
      <span class="tree-label">OBJECTS</span>
      <button
        type="button"
        class="refresh"
        title="Refresh"
        aria-label="Refresh object tree"
        data-testid="object-tree-refresh"
        @click="tree.refresh()"
      >
        ↻
      </button>
    </div>
    <input
      v-model="filter"
      class="filter"
      type="search"
      placeholder="Filter tables…"
      aria-label="Filter tables"
      data-testid="object-tree-filter"
    />

    <p v-if="loading" class="hint">Loading objects…</p>
    <p v-else-if="error" class="hint error">{{ error }}</p>
    <p v-else-if="!filtered.length" class="hint">No tables or views</p>

    <ul v-else class="nodes" data-testid="object-tree-nodes">
      <li v-for="obj in filtered" :key="obj.name" class="node">
        <button
          type="button"
          class="node-row"
          :aria-expanded="obj.expanded"
          :data-testid="`object-tree-table-${obj.name}`"
          @click="tree.toggleTable(obj.name)"
        >
          <span class="chevron" aria-hidden="true">{{
            obj.expanded ? "▾" : "▸"
          }}</span>
          <span class="name">{{ obj.name }}</span>
          <span class="kind">{{ obj.kind }}</span>
        </button>

        <ul v-if="obj.expanded" class="cols" :data-testid="`object-tree-cols-${obj.name}`">
          <li v-if="obj.loadingColumns" class="col hint-row">Loading…</li>
          <li v-else-if="obj.error" class="col hint-row error">{{ obj.error }}</li>
          <li
            v-for="col in obj.columns ?? []"
            :key="col.name"
            class="col"
          >
            <span class="col-name">
              {{ col.name }}
              <span v-if="col.is_primary_key" class="pk" title="Primary key">PK</span>
            </span>
            <span class="col-type">{{ col.data_type || "—" }}</span>
          </li>
        </ul>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.tree {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  min-height: 0;
}

.tree-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.tree-label {
  font-family: var(--q-font-mono);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.85px;
  color: var(--q-muted-foreground);
}

.refresh {
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  cursor: pointer;
  width: 1.5rem;
  height: 1.5rem;
  border-radius: var(--q-radius-sm);
  font-size: 14px;
  line-height: 1;
}

.refresh:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
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

.hint {
  margin: 4px 0 0;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.hint.error,
.hint-row.error,
.col.hint-row.error {
  color: var(--q-danger, #c44);
}

.nodes,
.cols {
  list-style: none;
  margin: 0;
  padding: 0;
}

.nodes {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.node-row {
  appearance: none;
  border: 0;
  background: transparent;
  width: 100%;
  display: grid;
  grid-template-columns: 1rem 1fr auto;
  align-items: center;
  gap: 4px;
  padding: 4px 6px;
  text-align: left;
  cursor: pointer;
  color: var(--q-foreground);
  font: inherit;
  font-size: 12px;
  border-radius: var(--q-radius-control);
}

.node-row:hover {
  background: var(--q-accent);
}

.chevron {
  color: var(--q-muted-foreground);
  font-size: 10px;
}

.name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 500;
}

.kind {
  font-size: 10px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.cols {
  padding: 0 0 4px 1rem;
}

.col {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 8px;
  padding: 2px 6px;
  font-size: 11px;
  color: var(--q-foreground);
}

.col-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pk {
  margin-left: 4px;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.4px;
  color: var(--q-primary);
  font-family: var(--q-font-mono);
}

.col-type {
  flex-shrink: 0;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
  font-size: 10px;
}

.hint-row {
  color: var(--q-muted-foreground);
}
</style>
