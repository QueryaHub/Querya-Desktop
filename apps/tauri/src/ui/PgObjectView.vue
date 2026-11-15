<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { storeToRefs } from "pinia";
import { useShellNavStore } from "../stores/shellNav";
import { useConnectionsStore } from "../stores/connections";
import { useShellStatusStore } from "../stores/shellStatus";
import {
  dbPostgresObjectDetail,
  formatConnectionError,
  type PostgresObjectDetail,
} from "../api/connection";

const nav = useShellNavStore();
const connections = useConnectionsStore();
const status = useShellStatusStore();
const { selectedObject } = storeToRefs(nav);

const loading = ref(false);
const error = ref<string | null>(null);
const detail = ref<PostgresObjectDetail | null>(null);

const conn = computed(() => {
  const id = selectedObject.value?.connectionId;
  return id ? (connections.byId.get(id) ?? null) : null;
});

const title = computed(() => {
  const d = detail.value;
  const obj = selectedObject.value;
  if (!d) return obj?.name ?? "Object";
  if (d.kind === "function" || d.kind === "sequence" || d.kind === "type") {
    return `${d.schema}.${d.name}`;
  }
  if (d.kind === "index" || d.kind === "trigger") {
    return `${d.schema}.${d.table}.${d.name}`;
  }
  const schemaFolderLabel: Record<
    "schema_indexes" | "schema_triggers" | "schema_types",
    string
  > = {
    schema_indexes: "Indexes",
    schema_triggers: "Triggers",
    schema_types: "Types",
  };
  return `${d.schema} · ${schemaFolderLabel[d.kind]}`;
});

async function load() {
  const obj = selectedObject.value;
  const c = conn.value;
  if (!obj?.objectId || !c || c.mock || c.driver !== "postgres") {
    detail.value = null;
    return;
  }
  loading.value = true;
  error.value = null;
  status.setQueryMetrics({ message: `Loading ${obj.name}…`, busy: true });
  try {
    detail.value = await dbPostgresObjectDetail(c.id, obj.objectId);
    status.setQueryMetrics({ message: title.value, busy: false });
  } catch (err) {
    detail.value = null;
    error.value = formatConnectionError(err);
    status.setQueryMetrics({ message: error.value, busy: false });
  } finally {
    loading.value = false;
  }
}

watch(
  () => [selectedObject.value?.objectId, selectedObject.value?.connectionId],
  () => {
    void load();
  },
  { immediate: true },
);

function formatBytes(b: number): string {
  if (b < 1024) return `${b} B`;
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(1)} KB`;
  return `${(b / (1024 * 1024)).toFixed(2)} MB`;
}
</script>

<template>
  <section class="pg-object" data-testid="pg-object-view">
    <header class="head">
      <div class="titles">
        <h2>{{ title }}</h2>
        <p class="sub">{{ selectedObject?.kind }}</p>
      </div>
      <button type="button" class="ghost" @click="nav.clearObject()">
        Back
      </button>
    </header>

    <div v-if="loading" class="state muted">Loading…</div>
    <div v-else-if="error" class="state err">{{ error }}</div>
    <template v-else-if="detail">
      <div v-if="detail.kind === 'function'" class="stack">
        <article
          v-for="(o, i) in detail.overloads"
          :key="i"
          class="card"
        >
          <h3>{{ o.signature }}</h3>
          <pre class="ddl">{{ o.definition }}</pre>
        </article>
      </div>

      <div v-else-if="detail.kind === 'sequence'" class="stack">
        <dl class="meta">
          <div><dt>Last value</dt><dd>{{ detail.last_value }}</dd></div>
          <div><dt>Start</dt><dd>{{ detail.start_value }}</dd></div>
          <div><dt>Min / Max</dt><dd>{{ detail.min_value }} / {{ detail.max_value }}</dd></div>
          <div><dt>Increment</dt><dd>{{ detail.increment_by }}</dd></div>
          <div><dt>Cache</dt><dd>{{ detail.cache_size }}</dd></div>
          <div><dt>Cycle</dt><dd>{{ detail.cycle ? "yes" : "no" }}</dd></div>
        </dl>
        <pre class="ddl">{{ detail.ddl }}</pre>
      </div>

      <div v-else-if="detail.kind === 'index'" class="stack">
        <p class="meta-line">
          Table <strong>{{ detail.table }}</strong>
          · {{ formatBytes(detail.size_bytes) }}
        </p>
        <pre class="ddl">{{ detail.definition }}</pre>
      </div>

      <div v-else-if="detail.kind === 'trigger'" class="stack">
        <p class="meta-line">
          Table <strong>{{ detail.table }}</strong>
        </p>
        <pre class="ddl">{{ detail.definition }}</pre>
      </div>

      <div v-else-if="detail.kind === 'type'" class="stack">
        <p class="meta-line">Kind: <strong>{{ detail.type_kind }}</strong></p>
      </div>

      <div v-else-if="detail.kind === 'schema_indexes'" class="list">
        <article v-for="(r, i) in detail.rows" :key="i" class="card">
          <h3>{{ r.table_name }}.{{ r.index_name }}</h3>
          <p class="meta-line">{{ formatBytes(r.size_bytes) }}</p>
          <pre class="ddl">{{ r.definition }}</pre>
        </article>
        <p v-if="!detail.rows.length" class="muted">No indexes in this schema.</p>
      </div>

      <div v-else-if="detail.kind === 'schema_triggers'" class="list">
        <article v-for="(r, i) in detail.rows" :key="i" class="card">
          <h3>{{ r.table_name }}.{{ r.trigger_name }}</h3>
          <pre class="ddl">{{ r.definition }}</pre>
        </article>
        <p v-if="!detail.rows.length" class="muted">No triggers in this schema.</p>
      </div>

      <div v-else-if="detail.kind === 'schema_types'" class="list">
        <article v-for="(r, i) in detail.rows" :key="i" class="card row">
          <h3>{{ r.name }}</h3>
          <span class="pill">{{ r.type_kind }}</span>
        </article>
        <p v-if="!detail.rows.length" class="muted">No user types in this schema.</p>
      </div>
    </template>
  </section>
</template>

<style scoped>
.pg-object {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  padding: 16px 20px 24px;
  gap: 12px;
}

.head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.titles h2 {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
}

.sub {
  margin: 2px 0 0;
  font-size: 11px;
  text-transform: uppercase;
  color: var(--q-muted-foreground);
}

.ghost {
  appearance: none;
  border: 1px solid var(--q-border);
  background: transparent;
  color: var(--q-foreground);
  border-radius: 6px;
  padding: 6px 10px;
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}

.ghost:hover {
  background: var(--q-accent);
}

.stack,
.list {
  display: flex;
  flex-direction: column;
  gap: 12px;
  overflow: auto;
  min-height: 0;
}

.card {
  border: 1px solid var(--q-border);
  border-radius: 8px;
  padding: 12px;
  background: color-mix(in srgb, var(--q-card) 80%, transparent);
}

.card.row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.card h3 {
  margin: 0 0 8px;
  font-size: 13px;
  font-weight: 600;
}

.card.row h3 {
  margin: 0;
}

.ddl {
  margin: 0;
  padding: 10px 12px;
  border-radius: 6px;
  background: color-mix(in srgb, var(--q-muted) 35%, transparent);
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 12px;
  line-height: 1.45;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.meta {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
  gap: 8px 16px;
  margin: 0;
}

.meta dt {
  font-size: 10px;
  text-transform: uppercase;
  color: var(--q-muted-foreground);
}

.meta dd {
  margin: 2px 0 0;
  font-size: 13px;
  font-weight: 500;
}

.meta-line {
  margin: 0 0 8px;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.pill {
  font-size: 11px;
  color: var(--q-muted-foreground);
  text-transform: uppercase;
}

.state {
  padding: 24px 0;
  font-size: 13px;
}

.muted {
  color: var(--q-muted-foreground);
}

.err {
  color: var(--q-destructive);
}
</style>
