<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { storeToRefs } from "pinia";
import { useWorkspaceStore } from "../stores/workspace";
import { useQueryResultStore } from "../stores/queryResult";
import { useShellNavStore } from "../stores/shellNav";
import { useConnectionsStore } from "../stores/connections";
import SqlEditor from "./SqlEditor.vue";
import ResultViewPane from "./ResultViewPane.vue";

const workspace = useWorkspaceStore();
const query = useQueryResultStore();
const connections = useConnectionsStore();
const nav = useShellNavStore();
const { activeTab } = storeToRefs(workspace);
const { columns, running, error, rowCount, elapsedMs, truncated, affectedRows } =
  storeToRefs(query);

const hasLiveConnection = computed(() => {
  const id = nav.selectedConnectionId;
  if (!id) return false;
  const c = connections.byId.get(id);
  return !!c && !c.mock;
});

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

const hasGrid = computed(() => columns.value.length > 0);
</script>

<template>
  <div class="sql-workspace" data-testid="sql-workspace">
    <div class="toolbar">
      <button
        type="button"
        class="run"
        data-testid="sql-run"
        :disabled="running || !hasLiveConnection"
        @click="onRun"
      >
        {{ running ? "Running…" : "Run" }}
      </button>
      <span class="hint">Parked under Overview · Ctrl/Cmd+Enter</span>
      <span v-if="!hasLiveConnection" class="warn">
        Live SQLite required for Run (Demo uses table Data view)
      </span>
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
      <div class="meta" v-if="hasGrid || affectedRows != null || error">
        <template v-if="error">{{ error }}</template>
        <template v-else-if="hasGrid">
          {{ rowCount }} rows
          <template v-if="elapsedMs != null"> · {{ elapsedMs }} ms</template>
          <template v-if="truncated"> · truncated</template>
        </template>
        <template v-else-if="affectedRows != null">
          {{ affectedRows }} rows affected
          <template v-if="elapsedMs != null"> · {{ elapsedMs }} ms</template>
        </template>
      </div>
      <p v-if="error" class="error">{{ error }}</p>
      <div v-else-if="hasGrid" class="grid-host">
        <ResultViewPane />
      </div>
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
  display: flex;
  flex-direction: column;
  overflow: hidden;
  padding: 8px 10px 10px;
  border-top: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
}

.meta {
  flex: 0 0 auto;
  font-size: 11px;
  color: var(--q-muted-foreground);
  margin-bottom: 6px;
  font-family: var(--q-font-mono);
}

.grid-host {
  flex: 1;
  min-height: 0;
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
</style>
