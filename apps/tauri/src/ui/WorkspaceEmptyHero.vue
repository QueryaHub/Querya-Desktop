<script setup lang="ts">
const emit = defineEmits<{
  newConnection: [];
  openSqlite: [];
  launchDemo: [];
  openTour: [];
}>();
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
    <p class="hint">
      Tip: <kbd>Ctrl</kbd>+<kbd>N</kbd> new connection ·
      <kbd>Ctrl</kbd>+<kbd>,</kbd> preferences · sidebar right-click → Create
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

.hint {
  margin: var(--q-space-4) 0 0;
  max-width: 32rem;
  font-size: 12px;
  color: var(--q-muted-foreground);
  line-height: 1.45;
}
</style>
