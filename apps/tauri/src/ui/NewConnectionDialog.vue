<script setup lang="ts">
import { computed, nextTick, onUnmounted, ref, watch } from "vue";
// Must not be named `open` — it would shadow the `open` prop/model in the
// template and make `v-if="open"` always truthy (Save connected, dialog stuck).
import { open as pickSqliteFile } from "@tauri-apps/plugin-dialog";
import QueryaButton from "./QueryaButton.vue";
import { QueryaIcon } from "./icons";

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

export type PostgresConnectPayload = {
  driver: "postgresql";
  name: string;
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
};

export type MysqlConnectPayload = {
  driver: "mysql";
  name: string;
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
};

export type RedisConnectPayload = {
  driver: "redis";
  name: string;
  host: string;
  port: number;
  database: string;
  username: string;
  password: string;
};

export type MongoConnectPayload = {
  driver: "mongodb";
  name: string;
  host: string;
  port: number;
  database: string;
  username: string;
  password: string;
  authSource: string;
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

/** Flutter: dialog owns dismiss via Navigator.pop — we mirror with v-model. */
const open = defineModel<boolean>("open", { required: true });
const emit = defineEmits<{
  connectSqlite: [payload: SqliteConnectPayload];
  connectPostgres: [payload: PostgresConnectPayload];
  connectMysql: [payload: MysqlConnectPayload];
  connectRedis: [payload: RedisConnectPayload];
  connectMongo: [payload: MongoConnectPayload];
}>();

function dismiss() {
  open.value = false;
}

type Step =
  | "pick"
  | "sqlite"
  | "postgres"
  | "mysql"
  | "redis"
  | "mongo"
  | "stub";

const step = ref<Step>("pick");
const category = ref<Category>("all");
const search = ref("");
const selectedId = ref<BuiltInDriverId | null>(null);
const searchEl = ref<HTMLInputElement | null>(null);
const nameEl = ref<HTMLInputElement | null>(null);

const name = ref("");
const path = ref("");
const readOnly = ref(false);
const host = ref("localhost");
const port = ref("5432");
const database = ref("querya");
const user = ref("querya");
const password = ref("querya");
const authSource = ref("admin");
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

const canSavePostgres = computed(() => {
  const p = Number(port.value);
  return (
    name.value.trim().length > 0 &&
    host.value.trim().length > 0 &&
    database.value.trim().length > 0 &&
    user.value.trim().length > 0 &&
    Number.isFinite(p) &&
    p > 0 &&
    p <= 65535
  );
});

const canSaveMysql = canSavePostgres;

const canSaveRedis = computed(() => {
  const p = Number(port.value);
  return (
    name.value.trim().length > 0 &&
    host.value.trim().length > 0 &&
    Number.isFinite(p) &&
    p > 0 &&
    p <= 65535
  );
});

const canSaveMongo = computed(() => {
  const p = Number(port.value);
  return (
    name.value.trim().length > 0 &&
    host.value.trim().length > 0 &&
    database.value.trim().length > 0 &&
    Number.isFinite(p) &&
    p > 0 &&
    p <= 65535
  );
});

function reset() {
  step.value = "pick";
  category.value = "all";
  search.value = "";
  selectedId.value = null;
  name.value = "";
  path.value = "";
  readOnly.value = false;
  host.value = "localhost";
  port.value = "5432";
  database.value = "querya";
  user.value = "querya";
  password.value = "querya";
  error.value = null;
  stubDriver.value = null;
}

watch(open, async (v) => {
  if (!v) return;
  reset();
  await nextTick();
  searchEl.value?.focus();
});

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
  if (choice.id === "postgresql") {
    step.value = "postgres";
    if (!name.value.trim()) name.value = "querya";
    port.value = "5432";
    void nextTick(() => nameEl.value?.focus());
    return;
  }
  if (choice.id === "mysql") {
    step.value = "mysql";
    if (!name.value.trim()) name.value = "mysql";
    port.value = "3306";
    database.value = "mysql";
    user.value = "root";
    password.value = "";
    void nextTick(() => nameEl.value?.focus());
    return;
  }
  if (choice.id === "redis") {
    step.value = "redis";
    if (!name.value.trim()) name.value = "redis";
    host.value = host.value.trim() || "127.0.0.1";
    port.value = "6379";
    database.value = "0";
    user.value = "";
    password.value = "";
    void nextTick(() => nameEl.value?.focus());
    return;
  }
  if (choice.id === "mongodb") {
    step.value = "mongo";
    if (!name.value.trim()) name.value = "mongo";
    host.value = host.value.trim() || "127.0.0.1";
    port.value = "27017";
    database.value = "querya";
    user.value = "querya";
    password.value = "querya";
    authSource.value = "admin";
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
    const selectedPath = await pickSqliteFile({
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
  // Flutter sqlite form: Navigator.pop after accept — dismiss first, then save.
  dismiss();
  emit("connectSqlite", { driver: "sqlite", name: n, path: p });
}

function submitPostgres() {
  error.value = null;
  const n = name.value.trim();
  const h = host.value.trim();
  const db = database.value.trim();
  const u = user.value.trim();
  const p = Number(port.value);
  if (!n) {
    error.value = "Connection name is required.";
    return;
  }
  if (!h || !db || !u || !Number.isFinite(p) || p <= 0) {
    error.value = "Host, port, database, and user are required.";
    return;
  }
  dismiss();
  emit("connectPostgres", {
    driver: "postgresql",
    name: n,
    host: h,
    port: p,
    database: db,
    user: u,
    password: password.value,
  });
}

function submitRedis() {
  error.value = null;
  const n = name.value.trim();
  const h = host.value.trim();
  const p = Number(port.value);
  const db = database.value.trim() || "0";
  if (!n) {
    error.value = "Connection name is required.";
    return;
  }
  if (!h || !Number.isFinite(p) || p <= 0 || p > 65535) {
    error.value = "Host and port are required.";
    return;
  }
  dismiss();
  emit("connectRedis", {
    driver: "redis",
    name: n,
    host: h,
    port: p,
    database: db,
    username: user.value.trim(),
    password: password.value,
  });
}

function submitMongo() {
  error.value = null;
  const n = name.value.trim();
  const h = host.value.trim();
  const db = database.value.trim();
  const p = Number(port.value);
  if (!n) {
    error.value = "Connection name is required.";
    return;
  }
  if (!h || !db || !Number.isFinite(p) || p <= 0 || p > 65535) {
    error.value = "Host, port and database are required.";
    return;
  }
  dismiss();
  emit("connectMongo", {
    driver: "mongodb",
    name: n,
    host: h,
    port: p,
    database: db,
    username: user.value.trim(),
    password: password.value,
    authSource: authSource.value.trim() || "admin",
  });
}

function submitMysql() {
  error.value = null;
  const n = name.value.trim();
  const h = host.value.trim();
  const db = database.value.trim();
  const u = user.value.trim();
  const p = Number(port.value);
  if (!n) {
    error.value = "Connection name is required.";
    return;
  }
  if (!h || !db || !u || !Number.isFinite(p) || p <= 0 || p > 65535) {
    error.value = "Host, port, database and user are required.";
    return;
  }
  dismiss();
  emit("connectMysql", {
    driver: "mysql",
    name: n,
    host: h,
    port: p,
    database: db,
    user: u,
    password: password.value,
  });
}


function onKey(e: KeyboardEvent) {
  if (!open.value) return;
  if (e.key === "Escape") {
    e.preventDefault();
    if (step.value !== "pick") goBack();
    else dismiss();
  } else if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    if (step.value === "pick" && canNext.value) goNext();
    else if (step.value === "sqlite" && canSaveSqlite.value) submitSqlite();
    else if (step.value === "postgres" && canSavePostgres.value)
      submitPostgres();
    else if (step.value === "mysql" && canSaveMysql.value) submitMysql();
    else if (step.value === "redis" && canSaveRedis.value) submitRedis();
    else if (step.value === "mongo" && canSaveMongo.value) submitMongo();
  }
}

watch(open, (v) => {
  if (v) window.addEventListener("keydown", onKey, true);
  else window.removeEventListener("keydown", onKey, true);
});

onUnmounted(() => window.removeEventListener("keydown", onKey, true));
</script>

<template>
  <!-- Teleport outside #app zoom so backdrop-filter (bokeh) can sample the UI. -->
  <Teleport to="body">
  <div
    v-if="open"
    class="overlay q-modal-scrim"
    data-testid="new-connection-dialog"
    @click.self="dismiss"
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
          <QueryaIcon class="search-ico" name="search" :size="14" />
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
        <QueryaButton variant="ghost" size="lg" @click="dismiss">
          Cancel
        </QueryaButton>
        <QueryaButton
          variant="primary"
          size="lg"
          :disabled="!canNext"
          @click="goNext"
        >
          Next
        </QueryaButton>
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
            <QueryaButton variant="secondary" size="lg" @click="browseSqlite">
              Browse…
            </QueryaButton>
          </div>
        </label>
        <label class="switch">
          <input v-model="readOnly" type="checkbox" />
          <span>Read-only mode</span>
        </label>
        <p v-if="error" class="err">{{ error }}</p>
      </div>

      <footer>
        <QueryaButton variant="ghost" size="lg" @click="goBack">
          Back
        </QueryaButton>
        <QueryaButton variant="ghost" size="lg" @click="dismiss">
          Cancel
        </QueryaButton>
        <QueryaButton
          variant="primary"
          size="lg"
          :disabled="!canSaveSqlite"
          @click="submitSqlite"
        >
          Save
        </QueryaButton>
      </footer>
    </div>

    <!-- Step 2b: PostgreSQL form -->
    <div
      v-else-if="step === 'postgres'"
      class="dialog form"
      role="dialog"
      aria-modal="true"
      aria-labelledby="ncd-pg-title"
    >
      <header class="hdr form-hdr">
        <h2 id="ncd-pg-title">New PostgreSQL Connection</h2>
        <p class="sub">Connect to a PostgreSQL server.</p>
      </header>

      <div class="body">
        <label class="field">
          <span>Connection name</span>
          <input
            ref="nameEl"
            v-model="name"
            type="text"
            placeholder="e.g. Local Postgres"
            maxlength="120"
          />
        </label>
        <div class="row2">
          <label class="field grow">
            <span>Host</span>
            <input v-model="host" type="text" spellcheck="false" />
          </label>
          <label class="field port">
            <span>Port</span>
            <input v-model="port" type="number" min="1" max="65535" />
          </label>
        </div>
        <label class="field">
          <span>Database</span>
          <input v-model="database" type="text" spellcheck="false" />
        </label>
        <label class="field">
          <span>User</span>
          <input v-model="user" type="text" spellcheck="false" autocomplete="username" />
        </label>
        <label class="field">
          <span>Password</span>
          <input
            v-model="password"
            type="password"
            autocomplete="current-password"
          />
        </label>
        <p class="hint-inline">
          Password is stored in the OS keyring (not in the profile database).
        </p>
        <p v-if="error" class="err">{{ error }}</p>
      </div>

      <footer>
        <QueryaButton variant="ghost" size="lg" @click="goBack">
          Back
        </QueryaButton>
        <QueryaButton variant="ghost" size="lg" @click="dismiss">
          Cancel
        </QueryaButton>
        <QueryaButton
          variant="primary"
          size="lg"
          :disabled="!canSavePostgres"
          @click="submitPostgres"
        >
          Save
        </QueryaButton>
      </footer>
    </div>

    <!-- Step 2c: MySQL form -->
    <div
      v-else-if="step === 'mysql'"
      class="dialog form"
      role="dialog"
      aria-modal="true"
      aria-labelledby="ncd-mysql-title"
      data-testid="mysql-connect-form"
    >
      <header class="hdr form-hdr">
        <h2 id="ncd-mysql-title">New MySQL Connection</h2>
        <p class="sub">Connect to a MySQL / MariaDB server.</p>
      </header>

      <div class="body">
        <label class="field">
          <span>Connection name</span>
          <input
            ref="nameEl"
            v-model="name"
            type="text"
            placeholder="e.g. Local MySQL"
            maxlength="120"
          />
        </label>
        <div class="row2">
          <label class="field grow">
            <span>Host</span>
            <input v-model="host" type="text" spellcheck="false" />
          </label>
          <label class="field port">
            <span>Port</span>
            <input v-model="port" type="number" min="1" max="65535" />
          </label>
        </div>
        <label class="field">
          <span>Database</span>
          <input v-model="database" type="text" spellcheck="false" />
        </label>
        <label class="field">
          <span>User</span>
          <input v-model="user" type="text" spellcheck="false" autocomplete="username" />
        </label>
        <label class="field">
          <span>Password</span>
          <input
            v-model="password"
            type="password"
            autocomplete="current-password"
          />
        </label>
        <p class="hint-inline">
          Password is stored in the OS keyring (not in the profile database).
        </p>
        <p v-if="error" class="err">{{ error }}</p>
      </div>

      <footer>
        <QueryaButton variant="ghost" size="lg" @click="goBack">
          Back
        </QueryaButton>
        <QueryaButton variant="ghost" size="lg" @click="dismiss">
          Cancel
        </QueryaButton>
        <QueryaButton
          variant="primary"
          size="lg"
          :disabled="!canSaveMysql"
          @click="submitMysql"
        >
          Save
        </QueryaButton>
      </footer>
    </div>

    <!-- Step 2d: Redis -->
    <div
      v-else-if="step === 'redis'"
      class="dialog form"
      role="dialog"
      aria-modal="true"
      aria-labelledby="ncd-redis-title"
    >
      <header class="hdr form-hdr">
        <h2 id="ncd-redis-title">New Redis Connection</h2>
        <p class="sub">Connect to a Redis server (SCAN / GET / SET).</p>
      </header>
      <div class="body form-body">
        <label>
          Name
          <input ref="nameEl" v-model="name" type="text" autocomplete="off" />
        </label>
        <label>
          Host
          <input v-model="host" type="text" autocomplete="off" />
        </label>
        <label>
          Port
          <input v-model="port" type="number" min="1" max="65535" />
        </label>
        <label>
          Database
          <input v-model="database" type="number" min="0" max="255" />
        </label>
        <label>
          Username
          <input
            v-model="user"
            type="text"
            autocomplete="username"
            placeholder="optional (ACL)"
          />
        </label>
        <label>
          Password
          <input
            v-model="password"
            type="password"
            autocomplete="current-password"
            placeholder="optional"
          />
        </label>
        <p v-if="error" class="err">{{ error }}</p>
      </div>
      <footer>
        <QueryaButton variant="ghost" size="lg" @click="goBack">
          Back
        </QueryaButton>
        <QueryaButton variant="ghost" size="lg" @click="dismiss">
          Cancel
        </QueryaButton>
        <QueryaButton
          variant="primary"
          size="lg"
          :disabled="!canSaveRedis"
          @click="submitRedis"
        >
          Save
        </QueryaButton>
      </footer>
    </div>

    <!-- Step 2e: MongoDB -->
    <div
      v-else-if="step === 'mongo'"
      class="dialog form"
      role="dialog"
      aria-modal="true"
      aria-labelledby="ncd-mongo-title"
    >
      <header class="hdr form-hdr">
        <h2 id="ncd-mongo-title">New MongoDB Connection</h2>
        <p class="sub">Connect to MongoDB (list collections + find).</p>
      </header>
      <div class="body form-body">
        <label>
          Name
          <input ref="nameEl" v-model="name" type="text" autocomplete="off" />
        </label>
        <label>
          Host
          <input v-model="host" type="text" autocomplete="off" />
        </label>
        <label>
          Port
          <input v-model="port" type="number" min="1" max="65535" />
        </label>
        <label>
          Database
          <input v-model="database" type="text" autocomplete="off" />
        </label>
        <label>
          Username
          <input
            v-model="user"
            type="text"
            autocomplete="username"
            placeholder="optional"
          />
        </label>
        <label>
          Password
          <input
            v-model="password"
            type="password"
            autocomplete="current-password"
            placeholder="optional"
          />
        </label>
        <label>
          Auth source
          <input v-model="authSource" type="text" autocomplete="off" />
        </label>
        <p v-if="error" class="err">{{ error }}</p>
      </div>
      <footer>
        <QueryaButton variant="ghost" size="lg" @click="goBack">
          Back
        </QueryaButton>
        <QueryaButton variant="ghost" size="lg" @click="dismiss">
          Cancel
        </QueryaButton>
        <QueryaButton
          variant="primary"
          size="lg"
          :disabled="!canSaveMongo"
          @click="submitMongo"
        >
          Save
        </QueryaButton>
      </footer>
    </div>

    <!-- Step 2f: stub for drivers without Tauri adapter yet -->
    <div
      v-else-if="step === 'stub'"
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
        <QueryaButton variant="ghost" size="lg" @click="goBack">
          Back
        </QueryaButton>
        <QueryaButton variant="primary" size="lg" @click="dismiss">
          Close
        </QueryaButton>
      </footer>
    </div>
  </div>
  </Teleport>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 2100;
  display: grid;
  place-items: center;
  padding: 4vh 4vw;
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

.row2 {
  display: flex;
  gap: 12px;
  align-items: flex-end;
}

.row2 .grow {
  flex: 1;
  min-width: 0;
}

.row2 .port {
  width: 96px;
  flex: 0 0 auto;
}

.hint-inline {
  margin: 0;
  font-size: 11.5px;
  font-weight: 400;
  line-height: 1.4;
  color: var(--q-muted-foreground);
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

</style>
