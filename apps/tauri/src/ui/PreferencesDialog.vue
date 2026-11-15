<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import {
  applyTheme,
  readStoredTheme,
  type QueryaThemeMode,
} from "../theme/queryaTheme";

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

type Category = "general" | "appearance" | "editor" | "about";

const category = ref<Category>("general");
const themeMode = ref<QueryaThemeMode>(readStoredTheme());

const categories: { id: Category; label: string }[] = [
  { id: "general", label: "General" },
  { id: "appearance", label: "Appearance" },
  { id: "editor", label: "Editor" },
  { id: "about", label: "About" },
];

const title = computed(
  () => categories.find((c) => c.id === category.value)?.label ?? "Preferences",
);

function setTheme(mode: QueryaThemeMode) {
  themeMode.value = mode;
  applyTheme(mode);
}

function onKey(e: KeyboardEvent) {
  if (!props.open) return;
  if (e.key === "Escape") {
    e.preventDefault();
    emit("close");
  }
}

watch(
  () => props.open,
  (v) => {
    if (v) {
      category.value = "general";
      themeMode.value = readStoredTheme();
    }
  },
);

onMounted(() => window.addEventListener("keydown", onKey));
onUnmounted(() => window.removeEventListener("keydown", onKey));
</script>

<template>
  <div
    v-if="open"
    class="overlay"
    data-testid="preferences-dialog"
    @click.self="emit('close')"
  >
    <div
      class="dialog q-glass"
      role="dialog"
      aria-modal="true"
      :aria-label="title"
    >
      <aside class="nav">
        <p class="nav-title">Preferences</p>
        <button
          v-for="c in categories"
          :key="c.id"
          type="button"
          class="nav-item"
          :class="{ active: category === c.id }"
          @click="category = c.id"
        >
          {{ c.label }}
        </button>
      </aside>
      <section class="pane">
        <header class="pane-head">
          <h2>{{ title }}</h2>
          <button
            type="button"
            class="x"
            aria-label="Close"
            @click="emit('close')"
          >
            ✕
          </button>
        </header>

        <div v-if="category === 'general'" class="body">
          <p class="lead">
            Preferences shell (Flutter master–detail). Persistence lands later.
          </p>
          <label class="row">
            <span>Confirm destructive queries</span>
            <input type="checkbox" checked disabled />
          </label>
          <label class="row">
            <span>Check for updates on startup</span>
            <input type="checkbox" checked disabled />
          </label>
        </div>

        <div v-else-if="category === 'appearance'" class="body">
          <p class="lead">Theme</p>
          <div class="seg">
            <button
              type="button"
              :class="{ on: themeMode === 'system' }"
              @click="setTheme('system')"
            >
              System
            </button>
            <button
              type="button"
              :class="{ on: themeMode === 'light' }"
              @click="setTheme('light')"
            >
              Light
            </button>
            <button
              type="button"
              :class="{ on: themeMode === 'dark' }"
              @click="setTheme('dark')"
            >
              Dark
            </button>
          </div>
        </div>

        <div v-else-if="category === 'editor'" class="body">
          <p class="lead">SQL editor options land with the editor polish pass.</p>
          <label class="row">
            <span>Font size</span>
            <span class="mono">13</span>
          </label>
        </div>

        <div v-else class="body">
          <p class="lead">Querya Desktop (Tauri)</p>
          <p class="muted">UI core · Fluid + Liquid Glass · no shadcn</p>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 2000;
  display: grid;
  place-items: center;
  background: color-mix(in srgb, #000 45%, transparent);
  padding: 24px;
}

.dialog {
  width: min(720px, 100%);
  height: min(480px, 100%);
  display: grid;
  grid-template-columns: 180px 1fr;
  border-radius: 12px;
  overflow: hidden;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
}

.nav {
  padding: 14px 10px;
  background: var(--q-sidebar-bg);
  border-right: 1px solid
    color-mix(in srgb, var(--q-border) 70%, transparent);
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.nav-title {
  margin: 0 8px 10px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--q-muted-foreground);
}

.nav-item {
  appearance: none;
  border: 0;
  background: transparent;
  text-align: left;
  padding: 8px 10px;
  border-radius: var(--q-radius-control);
  font: inherit;
  font-size: 12px;
  color: var(--q-foreground);
  cursor: pointer;
}

.nav-item.active,
.nav-item:hover {
  background: color-mix(in srgb, var(--q-primary) 16%, transparent);
}

.pane {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.pane-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  border-bottom: 1px solid
    color-mix(in srgb, var(--q-border) 70%, transparent);
}

.pane-head h2 {
  margin: 0;
  font-size: 14px;
  font-weight: 650;
}

.x {
  appearance: none;
  border: 0;
  background: transparent;
  width: 28px;
  height: 28px;
  border-radius: var(--q-radius-sm);
  color: var(--q-muted-foreground);
  cursor: pointer;
}

.x:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.body {
  padding: 16px 18px;
  overflow: auto;
}

.lead {
  margin: 0 0 14px;
  font-size: 13px;
  color: var(--q-foreground);
}

.muted {
  margin: 0;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 8px 0;
  font-size: 12px;
  border-bottom: 1px solid
    color-mix(in srgb, var(--q-border) 40%, transparent);
}

.seg {
  display: inline-flex;
  gap: 4px;
  padding: 3px;
  border-radius: var(--q-radius-control);
  background: var(--q-sidebar-bg);
}

.seg button {
  appearance: none;
  border: 0;
  background: transparent;
  padding: 6px 12px;
  border-radius: var(--q-radius-sm);
  font: inherit;
  font-size: 12px;
  color: var(--q-muted-foreground);
  cursor: pointer;
}

.seg button.on {
  background: var(--q-surface);
  color: var(--q-foreground);
  font-weight: 600;
}

.mono {
  font-family: var(--q-font-mono);
  color: var(--q-muted-foreground);
}
</style>
