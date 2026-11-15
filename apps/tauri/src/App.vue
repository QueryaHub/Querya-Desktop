<script setup lang="ts">
import { onMounted, ref } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { useShellStore } from "./stores/shell";
import {
  applyTheme,
  initTheme,
  type QueryaThemeMode,
} from "./theme/queryaTheme";

const shell = useShellStore();
const backend = ref<string>("…");
const theme = ref<QueryaThemeMode>("system");

const swatches = [
  { name: "bg", varName: "--q-background" },
  { name: "card", varName: "--q-card" },
  { name: "primary", varName: "--q-primary" },
  { name: "muted", varName: "--q-muted-foreground" },
  { name: "border", varName: "--q-border" },
  { name: "destructive", varName: "--q-destructive" },
] as const;

onMounted(async () => {
  theme.value = initTheme();
  try {
    const info = await invoke<{ name: string; stack: string; version: string }>(
      "app_info",
    );
    backend.value = `${info.name} ${info.version} (${info.stack})`;
  } catch (err) {
    backend.value = `IPC unavailable: ${String(err)}`;
  } finally {
    shell.markReady();
  }
});

function setTheme(mode: QueryaThemeMode) {
  theme.value = mode;
  applyTheme(mode);
}
</script>

<template>
  <div class="shell">
    <header class="brand">Querya</header>
    <p class="tagline">Tauri 2 + Vue 3 — Querya tokens (no shadcn)</p>
    <p class="meta" data-testid="backend-info">{{ backend }}</p>

    <div class="swatches" aria-label="Querya token swatches">
      <div v-for="s in swatches" :key="s.name" class="swatch">
        <span class="chip" :style="{ background: `var(${s.varName})` }" />
        <span class="label">{{ s.name }}</span>
      </div>
    </div>

    <div class="theme-row" role="group" aria-label="Theme">
      <button
        type="button"
        class="btn"
        :class="{ active: theme === 'system' }"
        @click="setTheme('system')"
      >
        System
      </button>
      <button
        type="button"
        class="btn"
        :class="{ active: theme === 'light' }"
        @click="setTheme('light')"
      >
        Light
      </button>
      <button
        type="button"
        class="btn"
        :class="{ active: theme === 'dark' }"
        @click="setTheme('dark')"
      >
        Dark
      </button>
    </div>
  </div>
</template>

<style scoped>
.shell {
  min-height: 100%;
  display: grid;
  place-content: center;
  gap: var(--q-space-2);
  padding: var(--q-space-8);
  text-align: center;
}

.brand {
  font-size: var(--q-text-hero);
  font-weight: 650;
  letter-spacing: -0.04em;
  margin: 0;
  color: var(--q-foreground);
}

.tagline {
  margin: 0;
  color: var(--q-muted-foreground);
}

.meta {
  margin: var(--q-space-3) 0 0;
  font-size: var(--q-text-sm);
  color: var(--q-muted-foreground);
  font-variant-numeric: tabular-nums;
}

.swatches {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: var(--q-space-3);
  margin-top: var(--q-space-6);
}

.swatch {
  display: grid;
  gap: var(--q-space-1);
  justify-items: center;
}

.chip {
  width: 2.25rem;
  height: 2.25rem;
  border-radius: var(--q-radius-md);
  border: 1px solid var(--q-border);
  box-shadow: var(--q-shadow-sm);
}

.label {
  font-size: var(--q-text-xs);
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.theme-row {
  display: inline-flex;
  gap: var(--q-space-2);
  margin-top: var(--q-space-6);
  padding: var(--q-space-1);
  border-radius: var(--q-radius-lg);
  background: var(--q-card);
  border: 1px solid var(--q-border);
}

.btn {
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  font: inherit;
  font-size: var(--q-text-sm);
  padding: var(--q-space-2) var(--q-space-3);
  border-radius: var(--q-radius-md);
  cursor: pointer;
}

.btn:hover {
  color: var(--q-foreground);
  background: var(--q-accent);
}

.btn.active {
  color: var(--q-primary-foreground);
  background: var(--q-primary);
}
</style>
