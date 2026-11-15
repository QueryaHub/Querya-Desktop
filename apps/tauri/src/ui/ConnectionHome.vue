<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { storeToRefs } from "pinia";
import {
  dbSqliteOverview,
  formatConnectionError,
  type SqliteOverview,
} from "../api/connection";
import { useConnectionsStore } from "../stores/connections";
import { useShellNavStore } from "../stores/shellNav";
import { useObjectTreeStore } from "../stores/objectTree";
import QueryaButton from "./QueryaButton.vue";
import SqlWorkspace from "./SqlWorkspace.vue";
import { QueryaIcon } from "./icons";
import ErdView from "./erd/ErdView.vue";

const connections = useConnectionsStore();
const nav = useShellNavStore();
const tree = useObjectTreeStore();
const { homeTab, selectedConnectionId } = storeToRefs(nav);

const conn = computed(() =>
  selectedConnectionId.value
    ? (connections.byId.get(selectedConnectionId.value) ?? null)
    : null,
);

const tables = computed(() =>
  tree.relations.filter((o) => o.kind === "table"),
);
const views = computed(() =>
  tree.relations.filter(
    (o) => o.kind === "view" || o.kind === "materialized_view",
  ),
);

const overview = ref<SqliteOverview | null>(null);
const loading = ref(false);
const error = ref<string | null>(null);

function formatBytes(bytes: number): string {
  if (bytes <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = bytes;
  let idx = 0;
  while (size >= 1024 && idx < units.length - 1) {
    size /= 1024;
    idx += 1;
  }
  return `${size.toFixed(idx === 0 ? 0 : 2)} ${units[idx]}`;
}

const sizeLabel = computed(() => {
  const info = overview.value;
  if (!info) return "—";
  const disk = info.file_size_bytes ?? 0;
  if (disk > 0) return formatBytes(disk);
  return formatBytes(info.page_count * info.page_size);
});

const pagesLabel = computed(() => {
  const info = overview.value;
  if (!info) return "—";
  return `${info.page_count} / ${info.page_size} B`;
});

async function loadOverview() {
  const c = conn.value;
  if (!c) return;
  if (c.driver !== "sqlite") {
    overview.value = null;
    error.value = null;
    loading.value = false;
    return;
  }
  if (c.mock) {
    overview.value = {
      version: "demo",
      page_count: 0,
      page_size: 0,
      journal_mode: "—",
      table_count: tables.value.length,
      file_size_bytes: null,
    };
    error.value = null;
    loading.value = false;
    return;
  }
  loading.value = true;
  error.value = null;
  try {
    overview.value = await dbSqliteOverview(c.id);
  } catch (err) {
    overview.value = null;
    error.value = formatConnectionError(err);
  } finally {
    loading.value = false;
  }
}

const isSqlite = computed(() => conn.value?.driver === "sqlite");
const isServerSql = computed(
  () =>
    conn.value?.driver === "postgres" || conn.value?.driver === "mysql",
);
const driverLabel = computed(() => {
  const d = conn.value?.driver;
  if (d === "sqlite") return "SQLite";
  if (d === "postgres") return "PostgreSQL";
  if (d === "mysql") return "MySQL";
  return d ?? "";
});
const endpointLabel = computed(() => {
  const c = conn.value;
  if (!c) return "";
  if (c.driver === "sqlite") return c.path ?? "";
  const port = c.port ?? (c.driver === "mysql" ? 3306 : 5432);
  return `${c.host ?? "localhost"}:${port}/${c.database ?? ""}`;
});

watch(
  selectedConnectionId,
  () => {
    void loadOverview();
  },
  { immediate: true },
);

function openRelation(o: { id: string; name: string; kind: string; schema?: string | null }) {
  if (!conn.value) return;
  if (
    o.kind !== "table" &&
    o.kind !== "view" &&
    o.kind !== "materialized_view"
  )
    return;
  nav.selectObject({
    connectionId: conn.value.id,
    name: o.name,
    kind: o.kind,
    objectId: o.id,
    schema: o.schema,
  });
}
</script>

<template>
  <div v-if="conn" class="home" data-testid="connection-home">
    <div class="strip" role="tablist" aria-label="Connection workspace">
      <button
        type="button"
        role="tab"
        class="tab"
        :class="{ active: homeTab === 'overview' }"
        :aria-selected="homeTab === 'overview'"
        data-testid="home-tab-overview"
        @click="nav.homeTab = 'overview'"
      >
        Overview
      </button>
      <button
        type="button"
        role="tab"
        class="tab"
        :class="{ active: homeTab === 'sql' }"
        :aria-selected="homeTab === 'sql'"
        data-testid="home-tab-sql"
        @click="nav.homeTab = 'sql'"
      >
        SQL
      </button>
      <button
        type="button"
        role="tab"
        class="tab"
        :class="{ active: homeTab === 'erd' }"
        :aria-selected="homeTab === 'erd'"
        data-testid="home-tab-erd"
        @click="nav.homeTab = 'erd'"
      >
        ER Diagram
      </button>
    </div>

    <div
      v-if="homeTab === 'overview'"
      class="overview"
      data-testid="home-overview"
    >
      <header class="head">
        <div class="mark" aria-hidden="true">
          <QueryaIcon name="database" :size="22" />
        </div>
        <div class="titles">
          <div class="title-row">
            <h1>{{ conn.name }}</h1>
            <span class="driver-pill">{{ driverLabel }}</span>
            <span v-if="conn.mock" class="badge">demo</span>
          </div>
          <p class="path">{{ endpointLabel }}</p>
        </div>
        <QueryaButton
          v-if="isSqlite"
          variant="secondary"
          size="md"
          :disabled="loading"
          @click="loadOverview"
        >
          Refresh
        </QueryaButton>
      </header>

      <template v-if="isServerSql">
        <section class="chips" aria-label="Database info">
          <div class="chip">
            <QueryaIcon class="chip-ico" name="server" :size="16" />
            <div class="chip-body">
              <span class="chip-l">Host</span>
              <span class="chip-v"
                >{{ conn.host }}:{{
                  conn.port ?? (conn.driver === "mysql" ? 3306 : 5432)
                }}</span
              >
            </div>
          </div>
          <div class="chip">
            <QueryaIcon class="chip-ico" name="database" :size="16" />
            <div class="chip-body">
              <span class="chip-l">Database</span>
              <span class="chip-v">{{ conn.database || "—" }}</span>
            </div>
          </div>
          <div class="chip">
            <QueryaIcon class="chip-ico" name="user" :size="16" />
            <div class="chip-body">
              <span class="chip-l">User</span>
              <span class="chip-v">{{ conn.user || "—" }}</span>
            </div>
          </div>
          <div class="chip">
            <QueryaIcon class="chip-ico" name="tableGroup" :size="16" />
            <div class="chip-body">
              <span class="chip-l">Schemas / tables</span>
              <span class="chip-v"
                >{{ tables.length }} tables · {{ views.length }} views</span
              >
            </div>
          </div>
        </section>
      </template>

      <p v-else-if="loading && !overview" class="status">
        Loading database overview…
      </p>
      <p v-else-if="error" class="status err">{{ error }}</p>

      <section
        v-else-if="isSqlite"
        class="chips"
        aria-label="Database info"
      >
        <div class="chip">
          <QueryaIcon class="chip-ico" name="info" :size="16" />
          <div class="chip-body">
            <span class="chip-l">SQLite Version</span>
            <span class="chip-v">{{ overview?.version || "—" }}</span>
          </div>
        </div>
        <div class="chip">
          <QueryaIcon class="chip-ico" name="hardDrive" :size="16" />
          <div class="chip-body">
            <span class="chip-l">Database Size</span>
            <span class="chip-v">{{ sizeLabel }}</span>
          </div>
        </div>
        <div class="chip">
          <QueryaIcon class="chip-ico" name="grid" :size="16" />
          <div class="chip-body">
            <span class="chip-l">Pages / Page Size</span>
            <span class="chip-v">{{ pagesLabel }}</span>
          </div>
        </div>
        <div class="chip">
          <QueryaIcon class="chip-ico" name="refresh" :size="16" />
          <div class="chip-body">
            <span class="chip-l">Journal Mode</span>
            <span class="chip-v">{{ overview?.journal_mode || "—" }}</span>
          </div>
        </div>
      </section>

      <section class="tables-card">
        <div class="card-head">
          <QueryaIcon class="card-ico" name="tableGroup" :size="16" />
          <h2>Tables</h2>
          <span class="count">{{ tables.length }}</span>
          <span v-if="views.length" class="count muted"
            >{{ views.length }} views</span
          >
        </div>
        <p v-if="tables.length === 0 && views.length === 0" class="empty">
          No user tables in database.
        </p>
        <div v-else class="wrap">
          <button
            v-for="o in tables"
            :key="o.id"
            type="button"
            class="table-chip"
            :title="`Open ${o.name}`"
            @click="openRelation(o)"
          >
            <QueryaIcon class="t-ico" name="table" :size="13" />
            {{ o.name }}
          </button>
          <button
            v-for="o in views"
            :key="o.id"
            type="button"
            class="table-chip view"
            :title="`Open ${o.name}`"
            @click="openRelation(o)"
          >
            <QueryaIcon class="t-ico" name="view" :size="13" />
            {{ o.name }}
          </button>
        </div>
      </section>
    </div>

    <div v-else-if="homeTab === 'sql'" class="sql-park" data-testid="home-sql">
      <SqlWorkspace />
    </div>

    <div v-else class="erd-park" data-testid="home-erd">
      <ErdView
        :connection-id="conn.id"
        :mock="!!conn.mock"
      />
    </div>
  </div>
</template>

<style scoped>
.home {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.strip {
  display: flex;
  gap: 2px;
  padding: 6px 10px 0;
  border-bottom: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  background: var(--q-sidebar-bg);
}

.tab {
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  font: inherit;
  font-size: 12px;
  font-weight: 600;
  padding: 8px 12px;
  cursor: pointer;
  border-radius: var(--q-radius-control) var(--q-radius-control) 0 0;
}

.tab.active {
  color: var(--q-foreground);
  background: var(--q-canvas);
  box-shadow: inset 0 -2px 0 var(--q-primary);
}

.overview {
  flex: 1;
  overflow: auto;
  padding: 24px;
  background: var(--q-canvas);
}

.head {
  display: flex;
  align-items: center;
  gap: 16px;
}

.mark {
  width: 44px;
  height: 44px;
  flex: 0 0 auto;
  display: grid;
  place-items: center;
  border-radius: 10px;
  background: color-mix(in srgb, var(--q-primary) 12%, transparent);
  color: var(--q-primary);
  font-size: 18px;
}

.titles {
  flex: 1;
  min-width: 0;
}

.title-row {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

h1 {
  margin: 0;
  font-size: 18px;
  font-weight: 650;
  letter-spacing: -0.02em;
}

.driver-pill {
  font-size: 10px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 4px;
  background: var(--q-muted);
  color: var(--q-muted-foreground);
}

.badge {
  font-size: 10px;
  padding: 1px 6px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--q-primary) 22%, transparent);
  color: var(--q-primary);
  font-weight: 700;
}

.path {
  margin: 4px 0 0;
  font-size: 13px;
  color: var(--q-muted-foreground);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.status {
  margin: 24px 0 0;
  font-size: 13px;
  color: var(--q-muted-foreground);
}

.status.err {
  color: var(--q-destructive);
}

.chips {
  margin-top: 24px;
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
}

@media (max-width: 900px) {
  .chips {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

.chip {
  min-height: 88px;
  display: flex;
  gap: 12px;
  align-items: center;
  padding: 12px 16px;
  border-radius: 10px;
  background: var(--q-card);
  border: 1px solid color-mix(in srgb, var(--q-border) 50%, transparent);
}

.chip-ico {
  flex: 0 0 auto;
  width: 20px;
  text-align: center;
  color: var(--q-primary);
  font-size: 16px;
  line-height: 1;
}

.chip-body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 2px;
}

.chip-l {
  display: block;
  font-size: 11px;
  line-height: 1.35;
  letter-spacing: 0.01em;
  color: var(--q-muted-foreground);
}

.chip-v {
  display: block;
  font-size: 13px;
  font-weight: 600;
  color: var(--q-foreground);
  line-height: 1.25;
  word-break: break-word;
}

.tables-card {
  margin-top: 24px;
  padding: 20px;
  border-radius: 12px;
  background: var(--q-card);
  border: 1px solid color-mix(in srgb, var(--q-border) 50%, transparent);
}

.card-head {
  display: flex;
  align-items: center;
  gap: 8px;
}

.card-ico {
  color: var(--q-primary);
}

.card-head h2 {
  margin: 0;
  font-size: 14px;
  font-weight: 650;
}

.count {
  font-size: 11px;
  padding: 2px 6px;
  border-radius: 4px;
  background: var(--q-muted);
  color: var(--q-muted-foreground);
}

.count.muted {
  opacity: 0.85;
}

.empty {
  margin: 24px 0 0;
  text-align: center;
  font-size: 13px;
  color: var(--q-muted-foreground);
}

.wrap {
  margin-top: 16px;
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.table-chip {
  appearance: none;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 10px;
  border-radius: 6px;
  border: 1px solid color-mix(in srgb, var(--q-border) 30%, transparent);
  background: color-mix(in srgb, var(--q-muted) 40%, transparent);
  color: var(--q-foreground);
  font: inherit;
  font-size: 13px;
  line-height: 1.25;
  cursor: pointer;
}

.table-chip:hover {
  background: color-mix(in srgb, var(--q-muted) 70%, transparent);
}

.table-chip.view {
  opacity: 0.95;
}

.t-ico {
  flex: 0 0 auto;
  width: 14px;
  text-align: center;
  color: var(--q-primary);
  font-size: 12px;
  line-height: 1;
}

.sql-park,
.erd-park {
  flex: 1;
  min-height: 0;
}
</style>
