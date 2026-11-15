<script setup lang="ts">
import { computed, nextTick, onUnmounted, ref, watch } from "vue";
import { open } from "@tauri-apps/plugin-dialog";

export type BuiltInDriverId =
  | "postgresql"
  | "mysql"
  | "sqlite"
  | "redis"
  | "mongodb";

export type SqliteConnectPayload = {
  driver: "sqlite";
  name: string;
  path: string;
};

type Category = "all" | "sql" | "nosql";

type DriverChoice = {
  id: BuiltInDriverId;
  label: string;
  category: "sql" | "nosql";
  /** Public URL under /drivers, or null → folder glyph */
  icon: string | null;
};

const DRIVERS: DriverChoice[] = [
  {
    id: "postgresql",
    label: "PostgreSQL",
    category: "sql",
    icon: "/drivers/postgresql_icon.png",
  },
  {
    id: "mysql",
    label: "MySQL",
    category: "sql",
    icon: "/drivers/mysql_icon.png",
  },
  {
    id: "sqlite",
    label: "SQLite",
    category: "sql",
    icon: null,
  },
  {
    id: "redis",
    label: "Redis",
    category: "nosql",
    icon: "/drivers/redis_icon.png",
  },
  {
    id: "mongodb",
    label: "MongoDB",
    category: "nosql",
    icon: "/drivers/mongodb_icon.png",
  },
];

const CATEGORY_ITEMS: { id: Category; label: string }[] = [
  { id: "all", label: "All databases" },
  { id: "sql", label: "SQL" },
  { id: "nosql", label: "NoSQL" },
];

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{
  close: [];
  connectSqlite: [payload: SqliteConnectPayload];
}>();

type Step = "pick" | "sqlite" | "stub";

const step = ref<Step>("pick");
const category = ref<Category>("all");
const search = ref("");
const selectedId = ref<BuiltInDriverId | null>(null);
const searchEl = ref<HTMLInputElement | null>(null);
const nameEl = ref<HTMLInputElement | null>(null);

const name = ref("");
const path = ref("");
const readOnly = ref(false);
const error = ref<string | null>(null);
const stubDriver = ref<DriverChoice | null>(null);

const categoryDrivers = computed(() => {
  if (category.value === "all") return DRIVERS;
  return DRIVERS.filter((d) => d.category === category.value);
});

const filteredDrivers = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return categoryDrivers.value;
  return categoryDrivers.value.filter((d) =>
    d.label.toLowerCase().includes(q),
  );
});

const selected = computed(
  () => DRIVERS.find((d) => d.id === selectedId.value) ?? null,
);

const canNext = computed(() => selected.value != null);

const canSaveSqlite = computed(
  () => name.value.trim().length > 0 && path.value.trim().length > 0,
);

function reset() {
  step.value = "pick";
  category.value = "all";
  search.value = "";
  selectedId.value = null;
  name.value = "";
  path.value = "";
  readOnly.value = false;
  error.value = null;
  stubDriver.value = null;
}

watch(
  () => props.open,
  async (v) => {
    if (!v) return;
    reset();
    await nextTick();
    searchEl.value?.focus();
  },
);

watch([category, search], () => {
  if (
    selectedId.value &&
    !filteredDrivers.value.some((d) => d.id === selectedId.value)
  ) {
    selectedId.value = null;
  }
});

function selectDriver(id: BuiltInDriverId) {
  selectedId.value = id;
}

function onCategoryChange(v: string) {
  category.value = (v as Category) || "all";
}

function onTypeChange(v: string) {
  selectedId.value = (v as BuiltInDriverId) || null;
}

function goNext() {
  const choice = selected.value;
  if (!choice) return;
  error.value = null;
  if (choice.id === "sqlite") {
    step.value = "sqlite";
    void nextTick(() => nameEl.value?.focus());
    return;
  }
  stubDriver.value = choice;
  step.value = "stub";
}

function goBack() {
  error.value = null;
  step.value = "pick";
  stubDriver.value = null;
}

async function browseSqlite() {
  try {
    const selectedPath = await open({
      multiple: false,
      directory: false,
      title: "Select SQLite database",
      filters: [
        { name: "SQLite", extensions: ["db", "sqlite", "sqlite3", "db3"] },
        { name: "All files", extensions: ["*"] },
      ],
    });
    if (!selectedPath || Array.isArray(selectedPath)) return;
    path.value = selectedPath;
    if (!name.value.trim()) {
      const base = selectedPath.split(/[/\\]/).pop() ?? selectedPath;
      name.value = base.replace(/\.(db|sqlite3?|db3)$/i, "") || base;
    }
  } catch (err) {
    if (String(err).includes("cancel")) return;
    error.value = String(err);
  }
}

function submitSqlite() {
  error.value = null;
  const p = path.value.trim();
  const n = name.value.trim();
  if (!n) {
    error.value = "Connection name is required.";
    return;
  }
  if (!p) {
    error.value = "Database file path is required.";
    return;
  }
  emit("connectSqlite", { driver: "sqlite", name: n, path: p });
  emit("close");
}

function onKey(e: KeyboardEvent) {
  if (!props.open) return;
  if (e.key === "Escape") {
    e.preventDefault();
    if (step.value !== "pick") goBack();
    else emit("close");
  } else if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    if (step.value === "pick" && canNext.value) goNext();
    else if (step.value === "sqlite" && canSaveSqlite.value) submitSqlite();
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
    <!-- Step 1: Select your database (Flutter parity) -->
    <div
      v-if="step === 'pick'"
      class="dialog pick"
      role="dialog"
      aria-modal="true"
      aria-labelledby="ncd-title"
    >
      <header class="hdr">
        <h2 id="ncd-title">Select your database</h2>
        <p class="sub">
          Create new database connection. Find your database driver in the list
          below.
        </p>
        <label class="search">
          <span class="search-ico" aria-hidden="true">⌕</span>
          <input
            ref="searchEl"
            v-model="search"
            type="search"
            placeholder="Search databases…"
            autocomplete="off"
            spellcheck="false"
          />
        </label>
        <div class="filters">
          <label class="filter">
            <span>Category</span>
            <select :value="category" @change="onCategoryChange(($event.target as HTMLSelectElement).value)">
              <option
                v-for="c in CATEGORY_ITEMS"
                :key="c.id"
                :value="c.id"
              >
                {{ c.label }}
              </option>
            </select>
          </label>
          <label class="filter">
            <span>Database type</span>
            <select
              :value="selectedId ?? ''"
              :disabled="filteredDrivers.length === 0"
              @change="onTypeChange(($event.target as HTMLSelectElement).value)"
            >
              <option value="" disabled>
                {{
                  filteredDrivers.length === 0
                    ? "No matches"
                    : "Select database…"
                }}
              </option>
              <option
                v-for="d in filteredDrivers"
                :key="d.id"
                :value="d.id"
              >
                {{ d.label }}
              </option>
            </select>
          </label>
        </div>
      </header>

      <div class="grid-wrap">
        <p v-if="filteredDrivers.length === 0" class="empty">
          No databases match your search.
        </p>
        <div v-else class="grid" role="listbox" aria-label="Database types">
          <button
            v-for="d in filteredDrivers"
            :key="d.id"
            type="button"
            role="option"
            class="card"
            :class="{ on: selectedId === d.id }"
            :aria-selected="selectedId === d.id"
            @click="selectDriver(d.id)"
            @dblclick="selectDriver(d.id); goNext()"
          >
            <span class="card-icon">
              <img
                v-if="d.icon"
                :src="d.icon"
                :alt="d.label"
                width="52"
                height="52"
              />
              <span v-else class="glyph folder" aria-hidden="true">
                <svg viewBox="0 0 24 24" width="48" height="48" fill="none">
                  <path
                    d="M3.5 7.5A1.5 1.5 0 0 1 5 6h4.2c.4 0 .8.16 1.06.44L11.5 8H19a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5v-10Z"
                    stroke="currentColor"
                    stroke-width="1.6"
                    fill="color-mix(in srgb, var(--q-primary) 18%, transparent)"
                  />
                </svg>
              </span>
            </span>
            <span class="card-label">{{ d.label }}</span>
          </button>
        </div>
      </div>

      <footer>
        <button type="button" class="btn ghost" @click="emit('close')">
          Cancel
        </button>
        <button
          type="button"
          class="btn primary"
          :disabled="!canNext"
          @click="goNext"
        >
          Next
        </button>
      </footer>
    </div>

    <!-- Step 2a: SQLite form -->
    <div
      v-else-if="step === 'sqlite'"
      class="dialog form"
      role="dialog"
      aria-modal="true"
      aria-labelledby="ncd-sqlite-title"
    >
      <header class="hdr form-hdr">
        <h2 id="ncd-sqlite-title">New SQLite Connection</h2>
        <p class="sub">Connect to a local SQLite database file.</p>
      </header>

      <div class="body">
        <label class="field">
          <span>Connection name</span>
          <input
            ref="nameEl"
            v-model="name"
            type="text"
            placeholder="e.g. Local Cache"
            maxlength="120"
          />
        </label>
        <label class="field">
          <span>Database file path</span>
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
        <label class="switch">
          <input v-model="readOnly" type="checkbox" />
          <span>Read-only mode</span>
        </label>
        <p v-if="error" class="err">{{ error }}</p>
      </div>

      <footer>
        <button type="button" class="btn ghost" @click="goBack">Back</button>
        <button type="button" class="btn ghost" @click="emit('close')">
          Cancel
        </button>
        <button
          type="button"
          class="btn primary"
          :disabled="!canSaveSqlite"
          @click="submitSqlite"
        >
          Save
        </button>
      </footer>
    </div>

    <!-- Step 2b: stub for drivers without Tauri adapter yet -->
    <div
      v-else
      class="dialog form"
      role="dialog"
      aria-modal="true"
      :aria-labelledby="'ncd-stub-title'"
    >
      <header class="hdr form-hdr">
        <h2 id="ncd-stub-title">New {{ stubDriver?.label }} Connection</h2>
        <p class="sub">
          {{ stubDriver?.label }} connects when the Tauri driver lands. The
          Flutter form fields will move here next.
        </p>
      </header>
      <div class="body stub-body">
        <div class="stub-icon">
          <img
            v-if="stubDriver?.icon"
            :src="stubDriver.icon"
            :alt="stubDriver.label"
            width="64"
            height="64"
          />
        </div>
        <p class="hint">
          Pick SQLite for a working local connection today, or Cancel and wait
          for the driver epic.
        </p>
      </div>
      <footer>
        <button type="button" class="btn ghost" @click="goBack">Back</button>
        <button type="button" class="btn primary" @click="emit('close')">
          Close
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
  display: flex;
  flex-direction: column;
  border-radius: 14px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  color: var(--q-foreground);
  box-shadow: 0 16px 48px color-mix(in srgb, #000 35%, transparent);
  overflow: hidden;
}

.dialog.pick {
  width: min(860px, 100%);
  height: min(680px, 85vh);
  min-height: min(320px, 85vh);
}

.dialog.form {
  width: min(520px, 100%);
  max-height: min(640px, 92vh);
}

.hdr {
  flex: 0 0 auto;
  padding: 20px 24px 8px;
  display: flex;
  flex-direction: column;
  gap: 0;
}

.form-hdr {
  padding-bottom: 4px;
}

h2 {
  margin: 0;
  font-size: 17px;
  font-weight: 650;
  letter-spacing: -0.01em;
}

.sub {
  margin: 6px 0 0;
  font-size: 12.5px;
  line-height: 1.45;
  color: var(--q-muted-foreground);
}

.search {
  margin-top: 12px;
  height: 36px;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 12px;
  border-radius: 8px;
  border: 1px solid color-mix(in srgb, var(--q-border) 55%, transparent);
  background: color-mix(in srgb, var(--q-muted-foreground) 10%, transparent);
}

.search:focus-within {
  border-color: color-mix(in srgb, var(--q-primary) 55%, transparent);
}

.search-ico {
  color: var(--q-muted-foreground);
  font-size: 14px;
  line-height: 1;
}

.search input {
  flex: 1;
  min-width: 0;
  border: 0;
  background: transparent;
  color: var(--q-foreground);
  font: inherit;
  font-size: 13px;
  outline: none;
}

.filters {
  margin-top: 12px;
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

@media (max-width: 520px) {
  .filters {
    grid-template-columns: 1fr;
  }
}

.filter {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.filter select {
  height: 36px;
  border-radius: 8px;
  border: 1px solid var(--q-border);
  background: var(--q-sidebar-bg);
  color: var(--q-foreground);
  padding: 0 10px;
  font: inherit;
  font-size: 13px;
}

.grid-wrap {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 16px;
}

.empty {
  margin: 40px 0;
  text-align: center;
  font-size: 13px;
  color: var(--q-muted-foreground);
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 12px;
}

@media (min-width: 700px) {
  .grid {
    grid-template-columns: repeat(4, 1fr);
  }
}

@media (min-width: 520px) and (max-width: 699px) {
  .grid {
    grid-template-columns: repeat(3, 1fr);
  }
}

.card {
  appearance: none;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 6px;
  min-height: 138px;
  padding: 10px 8px;
  border-radius: 10px;
  border: 1px solid color-mix(in srgb, var(--q-border) 35%, transparent);
  background: color-mix(in srgb, var(--q-muted-foreground) 8%, transparent);
  color: var(--q-foreground);
  cursor: pointer;
  font: inherit;
  transition:
    background 0.12s ease,
    border-color 0.12s ease;
}

.card:hover {
  background: color-mix(in srgb, var(--q-muted-foreground) 22%, transparent);
}

.card.on {
  background: color-mix(in srgb, var(--q-muted-foreground) 28%, transparent);
  border-color: color-mix(in srgb, var(--q-primary) 60%, transparent);
  border-width: 1.5px;
  padding: 9.5px 7.5px;
}

.card-icon {
  flex: 1;
  display: grid;
  place-items: center;
  min-height: 64px;
}

.card-icon img {
  width: 52px;
  height: 52px;
  object-fit: contain;
  pointer-events: none;
}

.glyph {
  font-size: 28px;
  font-weight: 700;
  line-height: 1;
  color: var(--q-muted-foreground);
}

.glyph.folder {
  color: var(--q-primary);
  display: grid;
  place-items: center;
}

.card-label {
  height: 38px;
  display: flex;
  align-items: center;
  justify-content: center;
  text-align: center;
  font-size: 13px;
  font-weight: 600;
  line-height: 1.2;
}

.body {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 12px 24px 8px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.stub-body {
  align-items: center;
  text-align: center;
  padding-top: 24px;
  padding-bottom: 24px;
}

.stub-icon img {
  object-fit: contain;
}

.field {
  display: flex;
  flex-direction: column;
  gap: 8px;
  font-size: 12px;
  font-weight: 600;
}

.field input {
  height: 36px;
  border-radius: 8px;
  border: 1px solid var(--q-border);
  background: var(--q-sidebar-bg);
  color: var(--q-foreground);
  padding: 0 12px;
  font: inherit;
  font-size: 13px;
  font-weight: 400;
}

.path-row {
  display: flex;
  gap: 10px;
}

.path-row input {
  flex: 1;
  min-width: 0;
}

.switch {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  font-weight: 400;
  cursor: pointer;
}

.hint {
  margin: 0;
  max-width: 36ch;
  font-size: 13px;
  line-height: 1.45;
  color: var(--q-muted-foreground);
}

.err {
  margin: 0;
  font-size: 12px;
  color: var(--q-destructive);
}

footer {
  flex: 0 0 auto;
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  padding: 14px 24px;
  border-top: 1px solid color-mix(in srgb, var(--q-border) 30%, transparent);
}

.btn {
  appearance: none;
  height: 36px;
  padding: 0 16px;
  border-radius: 8px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  color: var(--q-foreground);
  font: inherit;
  font-size: 13px;
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

.btn.ghost {
  border-color: transparent;
  background: transparent;
}

.btn.ghost:hover:not(:disabled) {
  background: var(--q-accent);
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
