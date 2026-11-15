<script setup lang="ts">
import { onMounted, ref, watch } from "vue";
import { storeToRefs } from "pinia";
import { formatConnectionError } from "../api/connection";
import { redisGet, redisScan, redisSet } from "../api/redis";
import { useShellNavStore } from "../stores/shellNav";
import { useConnectionsStore } from "../stores/connections";

const nav = useShellNavStore();
const connections = useConnectionsStore();
const { selectedConnectionId } = storeToRefs(nav);

const pattern = ref("*");
const keys = ref<string[]>([]);
const cursor = ref(0);
const loading = ref(false);
const error = ref<string | null>(null);
const selectedKey = ref<string | null>(null);
const value = ref("");
const valueDirty = ref(false);
const saving = ref(false);

async function loadKeys(reset: boolean) {
  const id = selectedConnectionId.value;
  if (!id) return;
  const conn = connections.byId.get(id);
  if (!conn || conn.driver !== "redis") return;

  loading.value = true;
  error.value = null;
  try {
    if (reset) {
      cursor.value = 0;
      keys.value = [];
    }
    const page = await redisScan(id, {
      cursor: cursor.value,
      pattern: pattern.value.trim() || "*",
      count: 100,
    });
    const merged = reset ? page.keys : [...keys.value, ...page.keys];
    keys.value = [...new Set(merged)].sort();
    cursor.value = page.nextCursor;
  } catch (err) {
    error.value = formatConnectionError(err);
  } finally {
    loading.value = false;
  }
}

async function selectKey(key: string) {
  const id = selectedConnectionId.value;
  if (!id) return;
  selectedKey.value = key;
  valueDirty.value = false;
  error.value = null;
  try {
    const v = await redisGet(id, key);
    value.value = v ?? "";
  } catch (err) {
    value.value = "";
    error.value = formatConnectionError(err);
  }
}

async function saveValue() {
  const id = selectedConnectionId.value;
  const key = selectedKey.value;
  if (!id || !key) return;
  saving.value = true;
  error.value = null;
  try {
    await redisSet(id, key, value.value);
    valueDirty.value = false;
  } catch (err) {
    error.value = formatConnectionError(err);
  } finally {
    saving.value = false;
  }
}

watch(selectedConnectionId, () => {
  selectedKey.value = null;
  value.value = "";
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
      <ul class="keys" data-testid="redis-key-list">
        <li
          v-for="k in keys"
          :key="k"
          :class="{ active: selectedKey === k }"
          @click="selectKey(k)"
        >
          {{ k }}
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
      <p v-if="!keys.length && !loading" class="empty">No keys</p>
    </aside>

    <section class="value-pane">
      <header v-if="selectedKey" class="value-hdr">
        <h2 data-testid="redis-selected-key">{{ selectedKey }}</h2>
        <button
          type="button"
          class="btn primary"
          data-testid="redis-save"
          :disabled="!valueDirty || saving"
          @click="saveValue"
        >
          {{ saving ? "Saving…" : "Save" }}
        </button>
      </header>
      <textarea
        v-if="selectedKey"
        v-model="value"
        class="value"
        data-testid="redis-value"
        spellcheck="false"
        @input="valueDirty = true"
      />
      <p v-else class="empty center">Select a key to view its value</p>
      <p v-if="error" class="err">{{ error }}</p>
    </section>
  </div>
</template>

<style scoped>
.redis-browser {
  height: 100%;
  min-height: 0;
  display: grid;
  grid-template-columns: minmax(180px, 280px) 1fr;
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
  padding: 6px 10px;
  font-size: 12px;
  font-family: var(--q-font-mono);
  cursor: pointer;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.keys li:hover {
  background: color-mix(in srgb, var(--q-foreground) 6%, transparent);
}

.keys li.active {
  background: color-mix(in srgb, var(--q-accent, #22d3ee) 22%, transparent);
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
  align-items: center;
  gap: 10px;
  margin-bottom: 8px;
}

.value-hdr h2 {
  margin: 0;
  flex: 1;
  min-width: 0;
  font-size: 13px;
  font-family: var(--q-font-mono);
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
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

.empty {
  margin: 12px;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.empty.center {
  margin: auto;
}

.err {
  margin: 8px 0 0;
  font-size: 12px;
  color: var(--q-danger, #ef4444);
}
</style>
