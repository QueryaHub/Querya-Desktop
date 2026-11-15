<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { storeToRefs } from "pinia";
import { formatConnectionError } from "../api/connection";
import {
  mongoFind,
  mongoListCollections,
  mongoListDatabases,
  type MongoFindResult,
} from "../api/mongo";
import { useShellNavStore } from "../stores/shellNav";
import { useConnectionsStore } from "../stores/connections";

const nav = useShellNavStore();
const connections = useConnectionsStore();
const { selectedConnectionId } = storeToRefs(nav);

const databases = ref<string[]>([]);
const collections = ref<string[]>([]);
const selectedDb = ref<string>("");
const selectedColl = ref<string | null>(null);
const filterJson = ref("{}");
const limit = ref(50);
const result = ref<MongoFindResult | null>(null);
const loadingDbs = ref(false);
const loadingCols = ref(false);
const loadingDocs = ref(false);
const error = ref<string | null>(null);

const prettyDocs = computed(() => {
  if (!result.value) return "";
  return JSON.stringify(result.value.documents, null, 2);
});

async function loadDatabases() {
  const id = selectedConnectionId.value;
  if (!id) return;
  const conn = connections.byId.get(id);
  if (!conn || conn.driver !== "mongo") return;

  loadingDbs.value = true;
  error.value = null;
  try {
    const names = await mongoListDatabases(id);
    databases.value = names.filter((n) => !n.startsWith("system.")).sort();
    const preferred = conn.database?.trim();
    selectedDb.value =
      preferred && databases.value.includes(preferred)
        ? preferred
        : (databases.value[0] ?? preferred ?? "");
    await loadCollections();
  } catch (err) {
    error.value = formatConnectionError(err);
    databases.value = [];
    collections.value = [];
  } finally {
    loadingDbs.value = false;
  }
}

async function loadCollections() {
  const id = selectedConnectionId.value;
  if (!id || !selectedDb.value) {
    collections.value = [];
    return;
  }
  loadingCols.value = true;
  error.value = null;
  selectedColl.value = null;
  result.value = null;
  try {
    collections.value = (await mongoListCollections(id, selectedDb.value)).sort();
  } catch (err) {
    error.value = formatConnectionError(err);
    collections.value = [];
  } finally {
    loadingCols.value = false;
  }
}

async function selectCollection(name: string) {
  selectedColl.value = name;
  await runFind();
}

async function runFind() {
  const id = selectedConnectionId.value;
  if (!id || !selectedDb.value || !selectedColl.value) return;

  loadingDocs.value = true;
  error.value = null;
  try {
    const raw = filterJson.value.trim();
    result.value = await mongoFind(id, {
      database: selectedDb.value,
      collection: selectedColl.value,
      filterJson: raw && raw !== "{}" ? raw : null,
      limit: limit.value,
    });
  } catch (err) {
    result.value = null;
    error.value = formatConnectionError(err);
  } finally {
    loadingDocs.value = false;
  }
}

watch(
  selectedConnectionId,
  () => {
    void loadDatabases();
  },
  { immediate: true },
);
</script>

<template>
  <div class="mongo-browser" data-testid="mongo-browser">
    <aside class="side">
      <label class="field">
        <span>Database</span>
        <select
          v-model="selectedDb"
          data-testid="mongo-db-select"
          :disabled="loadingDbs || databases.length === 0"
          @change="loadCollections"
        >
          <option v-for="db in databases" :key="db" :value="db">
            {{ db }}
          </option>
        </select>
      </label>
      <p v-if="loadingCols" class="muted">Loading collections…</p>
      <ul class="cols" data-testid="mongo-collection-list">
        <li v-for="c in collections" :key="c">
          <button
            type="button"
            class="col"
            :class="{ active: selectedColl === c }"
            :data-testid="`mongo-coll-${c}`"
            @click="selectCollection(c)"
          >
            {{ c }}
          </button>
        </li>
      </ul>
      <p v-if="!loadingCols && collections.length === 0" class="muted">
        No collections
      </p>
    </aside>

    <section class="main">
      <header class="toolbar">
        <h2 data-testid="mongo-selected-coll">
          {{ selectedColl ?? "Select a collection" }}
        </h2>
        <label class="field inline">
          <span>Filter</span>
          <input
            v-model="filterJson"
            type="text"
            data-testid="mongo-filter"
            spellcheck="false"
            placeholder="{}"
          />
        </label>
        <label class="field inline narrow">
          <span>Limit</span>
          <input
            v-model.number="limit"
            type="number"
            min="1"
            max="1000"
            data-testid="mongo-limit"
          />
        </label>
        <button
          type="button"
          class="run"
          data-testid="mongo-find"
          :disabled="!selectedColl || loadingDocs"
          @click="runFind"
        >
          Find
        </button>
      </header>

      <p v-if="error" class="err" data-testid="mongo-error">{{ error }}</p>
      <p v-else-if="loadingDocs" class="muted">Loading documents…</p>
      <template v-else-if="result">
        <p class="meta" data-testid="mongo-meta">
          {{ result.documents.length }} document{{
            result.documents.length === 1 ? "" : "s"
          }}
          <span v-if="result.truncated"> · truncated</span>
        </p>
        <pre class="docs" data-testid="mongo-documents">{{ prettyDocs }}</pre>
      </template>
      <p v-else class="muted">Pick a collection to load documents.</p>
    </section>
  </div>
</template>

<style scoped>
.mongo-browser {
  display: grid;
  grid-template-columns: minmax(180px, 240px) 1fr;
  gap: 0;
  min-height: 0;
  height: 100%;
  border: 1px solid var(--q-border);
  border-radius: 10px;
  overflow: hidden;
  background: var(--q-surface);
}

.side {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 0.75rem;
  border-right: 1px solid var(--q-border);
  min-height: 0;
  overflow: auto;
  background: color-mix(in srgb, var(--q-surface) 92%, var(--q-foreground) 8%);
}

.main {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
  min-height: 0;
  overflow: auto;
}

.toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.5rem 0.75rem;
}

.toolbar h2 {
  margin: 0;
  font-size: 1rem;
  font-weight: 600;
  margin-right: auto;
}

.field {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  font-size: 0.75rem;
  color: color-mix(in srgb, var(--q-foreground) 70%, transparent);
}

.field.inline {
  flex-direction: row;
  align-items: center;
  gap: 0.4rem;
}

.field.narrow input {
  width: 4.5rem;
}

.field select,
.field input {
  font: inherit;
  font-size: 0.85rem;
  color: var(--q-foreground);
  background: var(--q-surface);
  border: 1px solid var(--q-border);
  border-radius: 6px;
  padding: 0.35rem 0.5rem;
}

.field.inline input[type="text"] {
  min-width: 12rem;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
}

.cols {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
}

.col {
  width: 100%;
  text-align: left;
  border: none;
  background: transparent;
  color: var(--q-foreground);
  font: inherit;
  font-size: 0.85rem;
  padding: 0.35rem 0.45rem;
  border-radius: 6px;
  cursor: pointer;
}

.col:hover {
  background: color-mix(in srgb, var(--q-accent, #3b82f6) 12%, transparent);
}

.col.active {
  background: color-mix(in srgb, var(--q-accent, #3b82f6) 22%, transparent);
  font-weight: 600;
}

.run {
  font: inherit;
  font-size: 0.85rem;
  padding: 0.35rem 0.75rem;
  border-radius: 6px;
  border: 1px solid var(--q-border);
  background: var(--q-accent, #3b82f6);
  color: #fff;
  cursor: pointer;
}

.run:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.meta {
  margin: 0;
  font-size: 0.8rem;
  color: color-mix(in srgb, var(--q-foreground) 65%, transparent);
}

.docs {
  margin: 0;
  padding: 0.75rem;
  border-radius: 8px;
  border: 1px solid var(--q-border);
  background: color-mix(in srgb, var(--q-surface) 88%, #000 12%);
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 0.78rem;
  line-height: 1.45;
  white-space: pre-wrap;
  word-break: break-word;
  overflow: auto;
  flex: 1;
}

.muted {
  margin: 0;
  font-size: 0.85rem;
  color: color-mix(in srgb, var(--q-foreground) 55%, transparent);
}

.err {
  margin: 0;
  color: #ef4444;
  font-size: 0.85rem;
}
</style>
