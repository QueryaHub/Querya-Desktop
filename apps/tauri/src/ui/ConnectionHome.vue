<script setup lang="ts">
import { computed } from "vue";
import { storeToRefs } from "pinia";
import { useConnectionsStore } from "../stores/connections";
import { useShellNavStore } from "../stores/shellNav";
import { useObjectTreeStore } from "../stores/objectTree";
import SqlWorkspace from "./SqlWorkspace.vue";

const connections = useConnectionsStore();
const nav = useShellNavStore();
const tree = useObjectTreeStore();
const { homeTab, selectedConnectionId } = storeToRefs(nav);

const conn = computed(() =>
  selectedConnectionId.value
    ? connections.byId.get(selectedConnectionId.value) ?? null
    : null,
);

const tables = computed(() =>
  tree.relations.filter((o) => o.kind === "table"),
);
const views = computed(() =>
  tree.relations.filter((o) => o.kind === "view"),
);
</script>

<template>
  <div class="home" data-testid="connection-home" v-if="conn">
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
    </div>

    <div v-if="homeTab === 'overview'" class="overview" data-testid="home-overview">
      <header class="head">
        <h1>{{ conn.name }}</h1>
        <p class="meta">
          <span class="driver">{{ conn.driver }}</span>
          <span v-if="conn.mock" class="badge">demo</span>
          <span class="path">{{ conn.path }}</span>
        </p>
      </header>

      <section class="cards">
        <div class="card">
          <span class="n">{{ tables.length }}</span>
          <span class="l">Tables</span>
        </div>
        <div class="card">
          <span class="n">{{ views.length }}</span>
          <span class="l">Views</span>
        </div>
      </section>

      <section class="quick">
        <h2>Objects</h2>
        <p class="hint">
          Open a table from the sidebar to browse its <strong>Data</strong> grid —
          same as Flutter. SQL stays on this tab when you need it.
        </p>
        <ul class="obj-list">
          <li v-for="o in tree.relations" :key="o.id">
            <button
              type="button"
              class="obj"
              @click="
                nav.selectObject({
                  connectionId: conn!.id,
                  name: o.name,
                  kind: o.kind as 'table' | 'view',
                  objectId: o.id,
                  schema: o.schema,
                })
              "
            >
              <span class="obj-name">{{ o.name }}</span>
              <span class="obj-kind">{{ o.kind }}</span>
            </button>
          </li>
        </ul>
      </section>
    </div>

    <div v-else class="sql-park" data-testid="home-sql">
      <SqlWorkspace />
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
  padding: 24px 28px;
}

.head h1 {
  margin: 0;
  font-size: 22px;
  font-weight: 650;
  letter-spacing: -0.03em;
}

.meta {
  margin: 6px 0 0;
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  align-items: center;
  font-size: 12px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.driver {
  text-transform: uppercase;
  letter-spacing: 0.06em;
  font-size: 10px;
  font-weight: 700;
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
  opacity: 0.85;
}

.cards {
  display: flex;
  gap: 12px;
  margin: 22px 0;
}

.card {
  min-width: 88px;
  padding: 12px 14px;
  border-radius: var(--q-radius-control);
  background: var(--q-surface);
  border: 1px solid
    color-mix(in srgb, var(--q-border) 70%, transparent);
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.card .n {
  font-size: 20px;
  font-weight: 650;
  color: var(--q-foreground);
}

.card .l {
  font-size: 11px;
  color: var(--q-muted-foreground);
  text-transform: uppercase;
  letter-spacing: 0.06em;
}

.quick h2 {
  margin: 0 0 6px;
  font-size: 13px;
  font-weight: 650;
}

.hint {
  margin: 0 0 12px;
  font-size: 12px;
  color: var(--q-muted-foreground);
  max-width: 36rem;
  line-height: 1.45;
}

.obj-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
  max-width: 28rem;
}

.obj {
  appearance: none;
  width: 100%;
  border: 0;
  background: transparent;
  display: flex;
  justify-content: space-between;
  gap: 8px;
  padding: 8px 10px;
  border-radius: var(--q-radius-control);
  cursor: pointer;
  color: var(--q-foreground);
  font: inherit;
  font-size: 13px;
  text-align: left;
}

.obj:hover {
  background: var(--q-accent);
}

.obj-kind {
  font-size: 10px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.sql-park {
  flex: 1;
  min-height: 0;
}
</style>
