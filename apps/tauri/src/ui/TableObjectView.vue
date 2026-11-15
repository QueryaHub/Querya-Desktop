<script setup lang="ts">
import { computed, watch } from "vue";
import { storeToRefs } from "pinia";
import { useShellNavStore } from "../stores/shellNav";
import { useConnectionsStore } from "../stores/connections";
import { useQueryResultStore } from "../stores/queryResult";
import { useShellStatusStore } from "../stores/shellStatus";
import { findDemoObject } from "../mock/demoCatalog";
import { dbExecuteQuery } from "../api/query";
import { formatConnectionError } from "../api/connection";
import ResultGrid from "./ResultGrid.vue";
import { QueryaIcon } from "./icons";

const nav = useShellNavStore();
const connections = useConnectionsStore();
const query = useQueryResultStore();
const status = useShellStatusStore();
const { selectedObject, objectTab } = storeToRefs(nav);
const { columns, running, error, rowCount } = storeToRefs(query);

const conn = computed(() => {
  const id = selectedObject.value?.connectionId;
  return id ? (connections.byId.get(id) ?? null) : null;
});

async function loadTableData() {
  const obj = selectedObject.value;
  const c = conn.value;
  if (!obj || !c) return;

  query.reset();
  if (c.mock) {
    const demo = findDemoObject(obj.name);
    if (!demo) {
      query.setSnapshot({ columns: [], rows: [] });
      status.setQueryMetrics({
        message: `No mock data for ${obj.name}`,
        busy: false,
      });
      return;
    }
    query.setSnapshot({
      columns: demo.columns.map((col) => col.name),
      rows: demo.rows,
      message: `${demo.rows.length} rows · demo`,
    });
    return;
  }

  query.running = true;
  status.setQueryMetrics({ message: `Loading ${obj.name}…`, busy: true });
  try {
    const ident = (s: string) => `"${s.replace(/"/g, '""')}"`;
    const sql =
      c.driver === "postgres" && obj.schema
        ? `SELECT * FROM ${ident(obj.schema)}.${ident(obj.name)} LIMIT 200`
        : `SELECT * FROM ${ident(obj.name)} LIMIT 200`;
    await dbExecuteQuery(c.id, sql, (ev) => query.feedEvent(ev));
    status.setQueryMetrics({
      message: `${query.rowCount} rows · ${query.columns.length} cols`,
      busy: false,
      rows: query.rowCount,
      cols: query.columns.length,
      durationMs: query.elapsedMs,
    });
  } catch (err) {
    status.setQueryMetrics({
      message: formatConnectionError(err),
      busy: false,
    });
  } finally {
    query.running = false;
  }
}

watch(
  () =>
    [
      selectedObject.value?.name,
      selectedObject.value?.connectionId,
      objectTab.value,
    ] as const,
  () => {
    if (objectTab.value === "data") void loadTableData();
  },
  { immediate: true },
);
</script>

<template>
  <div
    v-if="selectedObject"
    class="table-view"
    data-testid="table-object-view"
  >
    <header class="chrome">
      <button type="button" class="back" aria-label="Back" @click="nav.clearObject()">
        <QueryaIcon name="arrowLeft" :size="16" />
      </button>
      <div class="titles">
        <h1>{{ selectedObject.name }}</h1>
        <p class="sub">
          {{ conn?.name }} · {{ selectedObject.kind }}
          <span v-if="conn?.mock" class="badge">demo</span>
        </p>
      </div>
      <div class="strip" role="tablist">
        <button
          type="button"
          class="tab"
          :class="{ active: objectTab === 'data' }"
          data-testid="object-tab-data"
          @click="nav.objectTab = 'data'"
        >
          Data
        </button>
        <button
          type="button"
          class="tab"
          :class="{ active: objectTab === 'relations' }"
          data-testid="object-tab-relations"
          @click="nav.objectTab = 'relations'"
        >
          Relations
        </button>
      </div>
    </header>

    <div v-if="objectTab === 'data'" class="data-pane">
      <div class="meta">
        <template v-if="running">Loading…</template>
        <template v-else-if="error">{{ error }}</template>
        <template v-else>
          {{ rowCount }} rows
          <template v-if="columns.length"> · {{ columns.length }} cols</template>
        </template>
      </div>
      <div v-if="!error && columns.length" class="grid-host">
        <ResultGrid />
      </div>
      <p v-else-if="!running && !error" class="empty">No rows</p>
    </div>

    <div v-else class="relations" data-testid="object-relations">
      <p class="empty">
        Relations / ER for this table lands with the diagram epic. Chrome only
        for now.
      </p>
    </div>
  </div>
</template>

<style scoped>
.table-view {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.chrome {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 12px;
  border-bottom: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  background: var(--q-sidebar-bg);
}

.back {
  appearance: none;
  border: 0;
  background: transparent;
  width: 28px;
  height: 28px;
  border-radius: var(--q-radius-sm);
  color: var(--q-muted-foreground);
  cursor: pointer;
  font-size: 14px;
}

.back:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.titles {
  flex: 1;
  min-width: 0;
}

.titles h1 {
  margin: 0;
  font-size: 14px;
  font-weight: 650;
}

.sub {
  margin: 2px 0 0;
  font-size: 11px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.badge {
  margin-left: 6px;
  font-size: 10px;
  padding: 1px 6px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--q-primary) 22%, transparent);
  color: var(--q-primary);
  font-weight: 700;
}

.strip {
  display: flex;
  gap: 2px;
}

.tab {
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  font: inherit;
  font-size: 12px;
  font-weight: 600;
  padding: 6px 10px;
  border-radius: var(--q-radius-control);
  cursor: pointer;
}

.tab.active {
  color: var(--q-foreground);
  background: color-mix(in srgb, var(--q-primary) 16%, transparent);
}

.data-pane {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  padding: 8px 10px 10px;
}

.meta {
  font-size: 11px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
  margin-bottom: 6px;
}

.grid-host {
  flex: 1;
  min-height: 0;
}

.relations {
  flex: 1;
  padding: 24px;
}

.empty {
  margin: 16px 0;
  font-size: 12px;
  color: var(--q-muted-foreground);
}
</style>
