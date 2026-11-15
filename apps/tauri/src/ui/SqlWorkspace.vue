<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { storeToRefs } from "pinia";
import { useWorkspaceStore } from "../stores/workspace";
import { useQueryResultStore } from "../stores/queryResult";
import { useConnectionsStore } from "../stores/connections";
import SqlEditor from "./SqlEditor.vue";

const workspace = useWorkspaceStore();
const query = useQueryResultStore();
const connections = useConnectionsStore();
const { activeTab } = storeToRefs(workspace);
const { columns, rows, running, error, rowCount, elapsedMs, truncated } =
  storeToRefs(query);

const editorRef = ref<InstanceType<typeof SqlEditor> | null>(null);

const sql = computed({
  get: () => {
    const id = activeTab.value?.id;
    return id ? workspace.sqlFor(id) : "";
  },
  set: (v: string) => {
    const id = activeTab.value?.id;
    if (id) workspace.setSql(id, v);
  },
});

watch(
  () => activeTab.value?.id,
  (id) => {
    if (id && activeTab.value?.kind === "sql") {
      workspace.ensureSql(id);
    }
  },
  { immediate: true },
);

async function onRun() {
  const text = editorRef.value?.getRunnableSql() ?? sql.value;
  await query.run(text);
}

const previewRows = computed(() => rows.value.slice(0, 50));
</script>

<template>
  <div class="sql-workspace" data-testid="sql-workspace">
    <div class="toolbar">
      <button
        type="button"
        class="run"
        data-testid="sql-run"
        :disabled="running || !connections.active"
        @click="onRun"
      >
        {{ running ? "Running…" : "Run" }}
      </button>
      <span class="hint">Ctrl/Cmd+Enter · selection or whole buffer</span>
      <span v-if="!connections.active" class="warn">Connect a database first</span>
    </div>
    <div class="editor-pane">
      <SqlEditor
        ref="editorRef"
        v-model="sql"
        :disabled="running"
        @run="onRun"
      />
    </div>
    <div class="result-pane" data-testid="sql-result-preview">
      <p v-if="error" class="error">{{ error }}</p>
      <template v-else-if="columns.length">
        <div class="meta">
          {{ rowCount }} rows
          <template v-if="elapsedMs != null"> · {{ elapsedMs }} ms</template>
          <template v-if="truncated"> · truncated</template>
          · preview (grid in #1876)
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th v-for="c in columns" :key="c">{{ c }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(row, i) in previewRows" :key="i">
                <td v-for="(cell, j) in row" :key="j">
                  {{ cell === null || cell === undefined ? "NULL" : String(cell) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
      <p v-else class="empty">Results appear here after Run.</p>
    </div>
  </div>
</template>

<style scoped>
.sql-workspace {
  height: 100%;
  min-height: 0;
  display: grid;
  grid-template-rows: auto minmax(140px, 42%) minmax(120px, 1fr);
  gap: 0;
}

.toolbar {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 6px 10px;
  border-bottom: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  background: var(--q-sidebar-bg);
}

.run {
  appearance: none;
  height: var(--q-control-h-sm);
  padding: 0 12px;
  border: 0;
  border-radius: var(--q-radius-control);
  background: var(--q-primary);
  color: var(--q-primary-foreground);
  font: inherit;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
}

.run:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.hint {
  font-size: 11px;
  color: var(--q-muted-foreground);
}

.warn {
  font-size: 11px;
  color: var(--q-danger, #c44);
  margin-left: auto;
}

.editor-pane {
  min-height: 0;
  padding: 8px 10px 0;
}

.result-pane {
  min-height: 0;
  overflow: auto;
  padding: 8px 10px 10px;
  border-top: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
}

.meta {
  font-size: 11px;
  color: var(--q-muted-foreground);
  margin-bottom: 6px;
  font-family: var(--q-font-mono);
}

.empty,
.error {
  margin: 12px 0;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.error {
  color: var(--q-danger, #c44);
}

.table-wrap {
  overflow: auto;
}

table {
  border-collapse: collapse;
  width: max-content;
  min-width: 100%;
  font-size: 12px;
  font-family: var(--q-font-mono);
}

th,
td {
  border: 1px solid
    color-mix(in srgb, var(--q-border) 70%, transparent);
  padding: 4px 8px;
  text-align: left;
  white-space: nowrap;
  max-width: 28rem;
  overflow: hidden;
  text-overflow: ellipsis;
}

th {
  background: var(--q-sidebar-bg);
  position: sticky;
  top: 0;
  font-weight: 600;
}
</style>
