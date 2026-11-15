<script setup lang="ts">
import { computed } from "vue";
import { useConnectionsStore } from "../stores/connections";

const emit = defineEmits<{
  newConnection: [];
  openSqlite: [];
  launchDemo: [];
  openTour: [];
  openRecent: [id: string];
}>();

const connections = useConnectionsStore();

const recents = computed(() => connections.items.slice(0, 5));
</script>

<template>
  <div class="hero" data-testid="workspace-empty-hero">
    <h1 class="brand">Querya</h1>
    <p class="lead">Connect to a database to start exploring.</p>
    <div class="actions">
      <button
        type="button"
        class="btn primary"
        data-testid="hero-new-connection"
        @click="emit('newConnection')"
      >
        New connection
      </button>
      <button
        type="button"
        class="btn"
        data-testid="hero-open-sqlite"
        @click="emit('openSqlite')"
      >
        Open SQLite file…
      </button>
      <button
        type="button"
        class="btn"
        data-testid="hero-demo"
        @click="emit('launchDemo')"
      >
        Demo
      </button>
      <button
        type="button"
        class="btn ghost"
        data-testid="hero-tour"
        @click="emit('openTour')"
      >
        Welcome tour
      </button>
    </div>

    <section v-if="recents.length" class="recents" data-testid="hero-recents">
      <h2>Recent</h2>
      <ul>
        <li v-for="c in recents" :key="c.id">
          <button type="button" class="recent" @click="emit('openRecent', c.id)">
            <span class="r-name">{{ c.name }}</span>
            <span class="r-meta">
              {{ c.driver }}<template v-if="c.mock"> · demo</template>
            </span>
          </button>
        </li>
      </ul>
    </section>

    <p class="hint">
      <kbd>Ctrl</kbd>+<kbd>P</kbd> command palette ·
      <kbd>Ctrl</kbd>+<kbd>K</kbd> go to object ·
      <kbd>Ctrl</kbd>+<kbd>,</kbd> preferences
    </p>
  </div>
</template>

<style scoped>
.hero {
  height: 100%;
  display: grid;
  place-content: center;
  justify-items: center;
  gap: var(--q-space-3);
  padding: var(--q-space-8);
  text-align: center;
  background: var(--q-canvas);
}

.brand {
  margin: 0;
  font-size: var(--q-text-hero);
  font-weight: 650;
  letter-spacing: -0.04em;
  color: var(--q-foreground);
}

.lead {
  margin: 0;
  max-width: 28rem;
  color: var(--q-muted-foreground);
  font-size: var(--q-text-sm);
}

.actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 8px;
  margin-top: var(--q-space-4);
}

.btn {
  appearance: none;
  height: var(--q-control-h);
  padding: 0 14px;
  border: 1px solid var(--q-border);
  border-radius: var(--q-radius-control);
  background: var(--q-surface);
  color: var(--q-foreground);
  font: inherit;
  font-size: 13px;
  cursor: pointer;
}

.btn:hover {
  background: var(--q-accent);
}

.btn.primary {
  background: var(--q-primary);
  border-color: transparent;
  color: var(--q-primary-foreground);
}

.btn.primary:hover {
  filter: brightness(1.05);
}

.btn.ghost {
  background: transparent;
}

.recents {
  margin-top: var(--q-space-5);
  width: min(22rem, 100%);
  text-align: left;
}

.recents h2 {
  margin: 0 0 8px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--q-muted-foreground);
}

.recents ul {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.recent {
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

.recent:hover {
  background: var(--q-accent);
}

.r-name {
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.r-meta {
  flex-shrink: 0;
  font-size: 11px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.hint {
  margin: var(--q-space-4) 0 0;
  max-width: 36rem;
  font-size: 12px;
  color: var(--q-muted-foreground);
  line-height: 1.45;
}

kbd {
  font-family: var(--q-font-mono);
  font-size: 11px;
  padding: 1px 5px;
  border-radius: 4px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
}
</style>
