<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { storeToRefs } from "pinia";
import { formatConnectionError } from "../api/connection";
import {
  redisKeyMetas,
  redisReadKey,
  redisScan,
  redisSet,
  type RedisKeyMeta,
  type RedisKeyView,
} from "../api/redis";
import { useShellNavStore } from "../stores/shellNav";
import { useConnectionsStore } from "../stores/connections";

const nav = useShellNavStore();
const connections = useConnectionsStore();
const { selectedConnectionId } = storeToRefs(nav);

const pattern = ref("*");
const metas = ref<RedisKeyMeta[]>([]);
const cursor = ref(0);
const loading = ref(false);
const scanError = ref<string | null>(null);
const keyError = ref<string | null>(null);
const selectedKey = ref<string | null>(null);
const view = ref<RedisKeyView | null>(null);
const stringEdit = ref("");
const valueDirty = ref(false);
const saving = ref(false);
const loadingKey = ref(false);

const canSave = computed(
  () =>
    view.value?.keyType === "string" && valueDirty.value && !saving.value,
);

function ttlLabel(ttl: number): string {
  if (ttl < 0) return "no expiry";
  if (ttl < 60) return `${ttl}s`;
  if (ttl < 3600) return `${Math.floor(ttl / 60)}m`;
  return `${Math.floor(ttl / 3600)}h`;
}

async function loadKeys(reset: boolean) {
  const id = selectedConnectionId.value;
  if (!id) return;
  const conn = connections.byId.get(id);
  if (!conn || conn.driver !== "redis") return;

  loading.value = true;
  scanError.value = null;
  try {
    if (reset) {
      cursor.value = 0;
      metas.value = [];
    }
    const page = await redisScan(id, {
      cursor: cursor.value,
      pattern: pattern.value.trim() || "*",
      count: 80,
    });
    const typed = page.keys.length
      ? await redisKeyMetas(id, page.keys)
      : [];
    const byKey = new Map(metas.value.map((m) => [m.key, m]));
    for (const m of typed) byKey.set(m.key, m);
    metas.value = [...byKey.values()].sort((a, b) =>
      a.key.localeCompare(b.key),
    );
    cursor.value = page.nextCursor;
  } catch (err) {
    scanError.value = formatConnectionError(err);
  } finally {
    loading.value = false;
  }
}

async function selectKey(key: string) {
  const id = selectedConnectionId.value;
  if (!id) return;
  selectedKey.value = key;
  valueDirty.value = false;
  keyError.value = null;
  loadingKey.value = true;
  view.value = null;
  try {
    const payload = await redisReadKey(id, key);
    view.value = payload;
    stringEdit.value = payload.stringValue ?? "";
  } catch (err) {
    view.value = null;
    stringEdit.value = "";
    keyError.value = formatConnectionError(err);
  } finally {
    loadingKey.value = false;
  }
}

async function saveValue() {
  const id = selectedConnectionId.value;
  const key = selectedKey.value;
  if (!id || !key || view.value?.keyType !== "string") return;
  saving.value = true;
  keyError.value = null;
  try {
    await redisSet(id, key, stringEdit.value);
    valueDirty.value = false;
    if (view.value) {
      view.value = { ...view.value, stringValue: stringEdit.value };
    }
  } catch (err) {
    keyError.value = formatConnectionError(err);
  } finally {
    saving.value = false;
  }
}

watch(selectedConnectionId, () => {
  selectedKey.value = null;
  view.value = null;
  stringEdit.value = "";
  void loadKeys(true);
});

onMounted(() => {
  void loadKeys(true);
});
</script>

<template>
  <div class="redis-browser" data-testid="redis-browser">
    <aside class="keys-pane">
      <div class="keys-toolbar">
        <input
          v-model="pattern"
          class="pattern"
          data-testid="redis-pattern"
          placeholder="MATCH pattern"
          @keydown.enter="loadKeys(true)"
        />
        <button
          type="button"
          class="btn"
          data-testid="redis-scan"
          :disabled="loading"
          @click="loadKeys(true)"
        >
          {{ loading ? "…" : "Scan" }}
        </button>
      </div>
      <p v-if="scanError" class="err pad">{{ scanError }}</p>
      <ul class="keys" data-testid="redis-key-list">
        <li
          v-for="m in metas"
          :key="m.key"
          :class="{ active: selectedKey === m.key }"
          @click="selectKey(m.key)"
        >
          <span class="k-name">{{ m.key }}</span>
          <span class="k-type">{{ m.keyType }}</span>
        </li>
      </ul>
      <button
        v-if="cursor !== 0"
        type="button"
        class="btn more"
        data-testid="redis-scan-more"
        :disabled="loading"
        @click="loadKeys(false)"
      >
        Scan more
      </button>
      <p v-if="!metas.length && !loading" class="empty">No keys</p>
    </aside>

    <section class="value-pane">
      <template v-if="selectedKey">
        <header class="value-hdr">
          <div class="titles">
            <div class="title-row">
              <span
                v-if="view"
                class="type-pill"
                data-testid="redis-key-type"
                >{{ view.keyType }}</span
              >
              <h2 data-testid="redis-selected-key">{{ selectedKey }}</h2>
            </div>
            <p v-if="view" class="ttl">TTL · {{ ttlLabel(view.ttl) }}</p>
          </div>
          <button
            v-if="view?.keyType === 'string'"
            type="button"
            class="btn primary"
            data-testid="redis-save"
            :disabled="!canSave"
            @click="saveValue"
          >
            {{ saving ? "Saving…" : "Save" }}
          </button>
        </header>

        <p v-if="keyError" class="err banner" data-testid="redis-key-error">
          {{ keyError }}
        </p>
        <p v-else-if="loadingKey" class="empty">Loading…</p>

        <textarea
          v-else-if="view?.keyType === 'string'"
          v-model="stringEdit"
          class="value"
          data-testid="redis-value"
          spellcheck="false"
          @input="valueDirty = true"
        />

        <div
          v-else-if="view?.keyType === 'hash'"
          class="table-wrap"
          data-testid="redis-hash"
        >
          <table>
            <thead>
              <tr>
                <th>Field</th>
                <th>Value</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="f in view.hashFields" :key="f.field">
                <td>{{ f.field }}</td>
                <td>{{ f.value }}</td>
              </tr>
            </tbody>
          </table>
          <p v-if="!view.hashFields.length" class="empty">Empty hash</p>
        </div>

        <ul
          v-else-if="view?.keyType === 'list'"
          class="members"
          data-testid="redis-list"
        >
          <li v-for="(item, i) in view.listValues" :key="i">
            <span class="idx">{{ i }}</span>
            {{ item }}
          </li>
          <li v-if="!view.listValues.length" class="empty">Empty list</li>
        </ul>

        <ul
          v-else-if="view?.keyType === 'set'"
          class="members"
          data-testid="redis-set"
        >
          <li v-for="m in view.setMembers" :key="m">{{ m }}</li>
          <li v-if="!view.setMembers.length" class="empty">Empty set</li>
        </ul>

        <div
          v-else-if="view?.keyType === 'zset'"
          class="table-wrap"
          data-testid="redis-zset"
        >
          <table>
            <thead>
              <tr>
                <th>Score</th>
                <th>Member</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="z in view.zsetMembers" :key="z.member">
                <td>{{ z.score }}</td>
                <td>{{ z.member }}</td>
              </tr>
            </tbody>
          </table>
          <p v-if="!view.zsetMembers.length" class="empty">Empty zset</p>
        </div>

        <p
          v-else-if="view"
          class="empty center"
          data-testid="redis-unsupported"
        >
          Unsupported type “{{ view.keyType }}” — string / hash / list / set /
          zset only in this stub.
        </p>
      </template>
      <p v-else class="empty center">Select a key to view its value</p>
    </section>
  </div>
</template>

<style scoped>
.redis-browser {
  height: 100%;
  min-height: 0;
  display: grid;
  grid-template-columns: minmax(200px, 300px) 1fr;
  gap: 0;
  background: var(--q-editor-bg);
  color: var(--q-foreground);
}

.keys-pane {
  display: flex;
  flex-direction: column;
  min-height: 0;
  border-right: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  background: var(--q-sidebar-bg);
}

.keys-toolbar {
  display: flex;
  gap: 6px;
  padding: 8px;
  flex-shrink: 0;
}

.pattern {
  flex: 1;
  min-width: 0;
  font: inherit;
  font-size: 12px;
  padding: 4px 8px;
  border-radius: 4px;
  border: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  background: var(--q-editor-bg);
  color: var(--q-foreground);
}

.btn {
  font: inherit;
  font-size: 12px;
  border: none;
  border-radius: 4px;
  padding: 4px 10px;
  cursor: pointer;
  background: color-mix(in srgb, var(--q-foreground) 8%, transparent);
  color: var(--q-foreground);
}

.btn:disabled {
  opacity: 0.45;
  cursor: default;
}

.btn.primary {
  background: var(--q-accent, #22d3ee);
  color: #0c0c0c;
  font-weight: 600;
}

.btn.more {
  margin: 0 8px 8px;
}

.keys {
  list-style: none;
  margin: 0;
  padding: 0 0 8px;
  overflow: auto;
  flex: 1;
  min-height: 0;
}

.keys li {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 10px;
  font-size: 12px;
  cursor: pointer;
}

.keys li:hover {
  background: color-mix(in srgb, var(--q-foreground) 6%, transparent);
}

.keys li.active {
  background: color-mix(in srgb, var(--q-accent, #22d3ee) 22%, transparent);
}

.k-name {
  flex: 1;
  min-width: 0;
  font-family: var(--q-font-mono);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.k-type {
  flex-shrink: 0;
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  opacity: 0.65;
}

.value-pane {
  display: flex;
  flex-direction: column;
  min-height: 0;
  min-width: 0;
  padding: 10px 12px;
}

.value-hdr {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  margin-bottom: 8px;
  flex-shrink: 0;
}

.titles {
  flex: 1;
  min-width: 0;
}

.title-row {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.type-pill {
  flex-shrink: 0;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  padding: 2px 7px;
  border-radius: 4px;
  background: color-mix(in srgb, var(--q-accent, #22d3ee) 22%, transparent);
}

.value-hdr h2 {
  margin: 0;
  min-width: 0;
  font-size: 13px;
  font-family: var(--q-font-mono);
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ttl {
  margin: 4px 0 0;
  font-size: 11px;
  color: var(--q-muted-foreground);
}

.value {
  flex: 1;
  min-height: 120px;
  resize: none;
  font: inherit;
  font-size: 13px;
  font-family: var(--q-font-mono);
  padding: 10px;
  border-radius: 6px;
  border: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  background: var(--q-sidebar-bg);
  color: var(--q-foreground);
}

.table-wrap {
  flex: 1;
  min-height: 0;
  overflow: auto;
}

table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
  font-family: var(--q-font-mono);
}

th,
td {
  text-align: left;
  padding: 6px 8px;
  border-bottom: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  vertical-align: top;
  word-break: break-word;
}

th {
  font-size: 11px;
  color: var(--q-muted-foreground);
  font-weight: 600;
}

.members {
  list-style: none;
  margin: 0;
  padding: 0;
  overflow: auto;
  flex: 1;
  min-height: 0;
  font-size: 12px;
  font-family: var(--q-font-mono);
}

.members li {
  padding: 5px 4px;
  border-bottom: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 50%),
      transparent
    );
}

.idx {
  display: inline-block;
  min-width: 28px;
  margin-right: 8px;
  color: var(--q-muted-foreground);
}

.empty {
  margin: 12px;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.empty.center {
  margin: auto;
}

.err {
  margin: 0;
  font-size: 12px;
  color: var(--q-danger, #ef4444);
}

.err.pad {
  padding: 0 10px 6px;
}

.err.banner {
  margin-bottom: 8px;
  padding: 8px 10px;
  border-radius: 6px;
  background: color-mix(in srgb, var(--q-danger, #ef4444) 12%, transparent);
}
</style>
