<script setup lang="ts">
import { onMounted, ref } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { useShellStore } from "./stores/shell";

const shell = useShellStore();
const backend = ref<string>("…");

onMounted(async () => {
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
</script>

<template>
  <div class="shell">
    <header class="brand">Querya</header>
    <p class="tagline">Tauri 2 + Vue 3 shell (scaffold)</p>
    <p class="meta" data-testid="backend-info">{{ backend }}</p>
  </div>
</template>

<style>
:root {
  color-scheme: light dark;
  font-family: "Segoe UI", "SF Pro Text", system-ui, sans-serif;
  line-height: 1.45;
  font-weight: 400;
  color: #1a1a1a;
  background: #f3f1ec;
  font-synthesis: none;
  text-rendering: optimizeLegibility;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

@media (prefers-color-scheme: dark) {
  :root {
    color: #f2f0ea;
    background: #161616;
  }
}

* {
  box-sizing: border-box;
}

html,
body,
#app {
  margin: 0;
  min-height: 100%;
  height: 100%;
}

.shell {
  min-height: 100%;
  display: grid;
  place-content: center;
  gap: 0.35rem;
  padding: 2rem;
  text-align: center;
}

.brand {
  font-size: clamp(2.5rem, 6vw, 4rem);
  font-weight: 650;
  letter-spacing: -0.04em;
  margin: 0;
}

.tagline {
  margin: 0;
  opacity: 0.72;
}

.meta {
  margin: 0.75rem 0 0;
  font-size: 0.875rem;
  opacity: 0.55;
  font-variant-numeric: tabular-nums;
}
</style>
