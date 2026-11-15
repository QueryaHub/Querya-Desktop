<script setup lang="ts">
import { computed, nextTick, onUnmounted, ref, watch } from "vue";
import { open } from "@tauri-apps/plugin-dialog";

export type ConnectionDriverChoice = "sqlite" | "postgres" | "mysql";

export type SqliteConnectPayload = {
  driver: "sqlite";
  name: string;
  path: string;
};

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{
  close: [];
  connectSqlite: [payload: SqliteConnectPayload];
}>();

const driver = ref<ConnectionDriverChoice>("sqlite");
const name = ref("");
const path = ref("");
const host = ref("localhost");
const port = ref(5432);
const database = ref("");
const user = ref("");
const password = ref("");
const ssl = ref(false);
const error = ref<string | null>(null);
const busy = ref(false);
const nameEl = ref<HTMLInputElement | null>(null);

const stubDrivers = computed(
  () => driver.value === "postgres" || driver.value === "mysql",
);

const canSave = computed(() => {
  if (busy.value) return false;
  if (driver.value === "sqlite") {
    return path.value.trim().length > 0;
  }
  return false;
});

function reset() {
  driver.value = "sqlite";
  name.value = "";
  path.value = "";
  host.value = "localhost";
  port.value = 5432;
  database.value = "";
  user.value = "";
  password.value = "";
  ssl.value = false;
  error.value = null;
  busy.value = false;
}

watch(
  () => props.open,
  async (v) => {
    if (!v) return;
    reset();
    await nextTick();
    nameEl.value?.focus();
  },
);

watch(driver, (d) => {
  error.value = null;
  if (d === "postgres") {
    port.value = 5432;
    user.value = "postgres";
  } else if (d === "mysql") {
    port.value = 3306;
    user.value = "root";
  }
});

async function browseSqlite() {
  try {
    const selected = await open({
      multiple: false,
      directory: false,
      title: "Select SQLite database",
      filters: [
        { name: "SQLite", extensions: ["db", "sqlite", "sqlite3"] },
        { name: "All files", extensions: ["*"] },
      ],
    });
    if (!selected || Array.isArray(selected)) return;
    path.value = selected;
    if (!name.value.trim()) {
      const base = selected.split(/[/\\]/).pop() ?? selected;
      name.value = base.replace(/\.(db|sqlite3?)$/i, "") || base;
    }
  } catch (err) {
    if (String(err).includes("cancel")) return;
    error.value = String(err);
  }
}

function fileName(p: string): string {
  const parts = p.split(/[/\\]/);
  return parts[parts.length - 1] || p;
}

function submit() {
  error.value = null;
  if (driver.value === "sqlite") {
    const p = path.value.trim();
    if (!p) {
      error.value = "Choose a database file";
      return;
    }
    const n = name.value.trim() || fileName(p);
    emit("connectSqlite", { driver: "sqlite", name: n, path: p });
    emit("close");
    return;
  }
  error.value =
    driver.value === "postgres"
      ? "PostgreSQL connect lands with the driver epic — fields are ready for wiring."
      : "MySQL connect lands with the driver epic — fields are ready for wiring.";
}

function onKey(e: KeyboardEvent) {
  if (!props.open) return;
  if (e.key === "Escape") {
    e.preventDefault();
    emit("close");
  } else if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    submit();
  }
}

watch(
  () => props.open,
  (v) => {
    if (v) window.addEventListener("keydown", onKey, true);
    else window.removeEventListener("keydown", onKey, true);
  },
);

onUnmounted(() => window.removeEventListener("keydown", onKey, true));
</script>

<template>
  <div
    v-if="open"
    class="overlay"
    data-testid="new-connection-dialog"
    @click.self="emit('close')"
  >
    <div
      class="dialog"
      role="dialog"
      aria-modal="true"
      aria-label="New Connection"
    >
      <header class="hdr">
        <h2>New Connection</h2>
        <button
          type="button"
          class="x"
          aria-label="Close"
          @click="emit('close')"
        >
          ✕
        </button>
      </header>

      <div class="drivers" role="tablist" aria-label="Database driver">
        <button
          type="button"
          role="tab"
          class="drv"
          :class="{ on: driver === 'sqlite' }"
          :aria-selected="driver === 'sqlite'"
          @click="driver = 'sqlite'"
        >
          SQLite
        </button>
        <button
          type="button"
          role="tab"
          class="drv"
          :class="{ on: driver === 'postgres' }"
          :aria-selected="driver === 'postgres'"
          @click="driver = 'postgres'"
        >
          PostgreSQL
        </button>
        <button
          type="button"
          role="tab"
          class="drv"
          :class="{ on: driver === 'mysql' }"
          :aria-selected="driver === 'mysql'"
          @click="driver = 'mysql'"
        >
          MySQL
        </button>
      </div>

      <div class="body">
        <!-- SQLite -->
        <template v-if="driver === 'sqlite'">
          <label class="field">
            <span>Connection name</span>
            <input
              ref="nameEl"
              v-model="name"
              type="text"
              placeholder="My database"
              maxlength="120"
            />
          </label>
          <label class="field">
            <span>Database file</span>
            <div class="path-row">
              <input
                v-model="path"
                type="text"
                placeholder="/path/to/database.db"
                spellcheck="false"
              />
              <button type="button" class="btn" @click="browseSqlite">
                Browse…
              </button>
            </div>
          </label>
          <p class="hint">
            Opens a local SQLite file. You can also use Open SQLite from the
            empty workspace.
          </p>
        </template>

        <!-- PG / MySQL stubs -->
        <template v-else>
          <label class="field">
            <span>Connection name</span>
            <input
              ref="nameEl"
              v-model="name"
              type="text"
              :placeholder="driver === 'postgres' ? 'Postgres' : 'MySQL'"
              maxlength="120"
            />
          </label>
          <div class="grid2">
            <label class="field">
              <span>Host</span>
              <input v-model="host" type="text" spellcheck="false" />
            </label>
            <label class="field">
              <span>Port</span>
              <input v-model.number="port" type="number" min="1" max="65535" />
            </label>
          </div>
          <label class="field">
            <span>Database</span>
            <input v-model="database" type="text" spellcheck="false" />
          </label>
          <div class="grid2">
            <label class="field">
              <span>Username</span>
              <input v-model="user" type="text" spellcheck="false" />
            </label>
            <label class="field">
              <span>Password</span>
              <input v-model="password" type="password" autocomplete="off" />
            </label>
          </div>
          <label class="switch">
            <input v-model="ssl" type="checkbox" />
            <span>Use SSL / TLS</span>
          </label>
          <p class="hint warn">
            {{
              driver === "postgres" ? "PostgreSQL" : "MySQL"
            }}
            adapter is next — fields match Flutter; Save connects when the
            driver lands.
          </p>
        </template>

        <p v-if="error" class="err">{{ error }}</p>
      </div>

      <footer>
        <button type="button" class="btn" @click="emit('close')">Cancel</button>
        <button
          type="button"
          class="btn primary"
          :disabled="stubDrivers ? false : !canSave"
          @click="submit"
        >
          {{ stubDrivers ? "Save (soon)" : "Save" }}
        </button>
      </footer>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 2100;
  display: grid;
  place-items: center;
  padding: 4vh 4vw;
  background: color-mix(in srgb, #000 45%, transparent);
}

.dialog {
  width: min(520px, 100%);
  max-height: min(640px, 92vh);
  display: flex;
  flex-direction: column;
  border-radius: 14px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  color: var(--q-foreground);
  box-shadow: 0 16px 48px color-mix(in srgb, #000 35%, transparent);
  overflow: hidden;
}

.hdr {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 16px 10px 18px;
  border-bottom: 1px solid color-mix(in srgb, var(--q-border) 40%, transparent);
}

h2 {
  margin: 0;
  font-size: 15px;
  font-weight: 650;
}

.x {
  appearance: none;
  border: 0;
  background: transparent;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  color: var(--q-muted-foreground);
  cursor: pointer;
}

.x:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.drivers {
  display: flex;
  gap: 6px;
  padding: 12px 16px 0;
}

.drv {
  appearance: none;
  border: 1px solid var(--q-border);
  background: transparent;
  color: var(--q-muted-foreground);
  border-radius: 999px;
  padding: 5px 12px;
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}

.drv.on {
  background: color-mix(in srgb, var(--q-primary) 16%, transparent);
  border-color: transparent;
  color: var(--q-primary);
  font-weight: 600;
}

.body {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 14px 18px 8px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.field {
  display: flex;
  flex-direction: column;
  gap: 5px;
  font-size: 12px;
}

.field input {
  height: 32px;
  border-radius: 6px;
  border: 1px solid var(--q-border);
  background: var(--q-sidebar-bg);
  color: var(--q-foreground);
  padding: 0 10px;
  font: inherit;
  font-size: 12px;
}

.path-row {
  display: flex;
  gap: 8px;
}

.path-row input {
  flex: 1;
  min-width: 0;
}

.grid2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}

.switch {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  cursor: pointer;
}

.hint {
  margin: 0;
  font-size: 11px;
  line-height: 1.4;
  color: var(--q-muted-foreground);
}

.hint.warn {
  color: color-mix(in srgb, var(--q-warning, #d97706) 85%, var(--q-foreground));
}

.err {
  margin: 0;
  font-size: 12px;
  color: var(--q-destructive);
}

footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  padding: 12px 16px 14px;
  border-top: 1px solid color-mix(in srgb, var(--q-border) 40%, transparent);
}

.btn {
  appearance: none;
  height: 32px;
  padding: 0 14px;
  border-radius: 6px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  color: var(--q-foreground);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
  white-space: nowrap;
}

.btn:hover:not(:disabled) {
  background: var(--q-accent);
}

.btn:disabled {
  opacity: 0.45;
  cursor: default;
}

.btn.primary {
  background: var(--q-primary);
  border-color: transparent;
  color: var(--q-primary-foreground);
}

.btn.primary:hover:not(:disabled) {
  filter: brightness(1.06);
}
</style>
