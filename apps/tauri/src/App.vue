<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { useShellStore } from "./stores/shell";
import {
  applyTheme,
  initTheme,
  type QueryaThemeMode,
} from "./theme/queryaTheme";
import {
  provideQueryaMotion,
  type QueryaMotionLevel,
} from "./motion";

const shell = useShellStore();
const motion = provideQueryaMotion();
const { level: motionLevel, springsOn } = motion;
const backend = ref<string>("…");
const theme = ref<QueryaThemeMode>("system");
const panelOpen = ref(false);

const swatches = [
  { name: "bg", varName: "--q-background" },
  { name: "card", varName: "--q-card" },
  { name: "primary", varName: "--q-primary" },
  { name: "muted", varName: "--q-muted-foreground" },
  { name: "border", varName: "--q-border" },
  { name: "destructive", varName: "--q-destructive" },
] as const;

const panelStyle = computed(() => ({
  transitionDuration: `${motion.duration("standard")}ms`,
  transitionTimingFunction: motion.easing("enter"),
}));

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

function setMotion(level: QueryaMotionLevel) {
  motion.setLevel(level);
}
</script>

<template>
  <div class="shell">
    <header class="brand">Querya</header>
    <p class="tagline">Tauri 2 + Vue 3 — tokens + Fluid Motion</p>
    <p class="meta" data-testid="backend-info">{{ backend }}</p>
    <p class="meta">
      springs: {{ springsOn ? "on" : "off" }} · level: {{ motionLevel }}
    </p>

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

    <div class="theme-row" role="group" aria-label="Motion">
      <button
        type="button"
        class="btn"
        :class="{ active: motionLevel === 'full' }"
        @click="setMotion('full')"
      >
        Full
      </button>
      <button
        type="button"
        class="btn"
        :class="{ active: motionLevel === 'reduced' }"
        @click="setMotion('reduced')"
      >
        Reduced
      </button>
      <button
        type="button"
        class="btn"
        :class="{ active: motionLevel === 'off' }"
        @click="setMotion('off')"
      >
        Off
      </button>
    </div>

    <button type="button" class="btn demo-toggle" @click="panelOpen = !panelOpen">
      Toggle demo panel
    </button>
    <div
      class="demo-panel"
      :class="{ open: panelOpen }"
      :style="panelStyle"
      data-testid="motion-demo-panel"
    />
  </div>
</template>

<style scoped>
.shell {
  min-height: 100%;
  display: grid;
  place-content: center;
  justify-items: center;
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
  margin: var(--q-space-1) 0 0;
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
  margin-top: var(--q-space-4);
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

.demo-toggle {
  margin-top: var(--q-space-4);
  background: var(--q-secondary);
  color: var(--q-secondary-foreground);
  border: 1px solid var(--q-border);
}

.demo-panel {
  width: 12rem;
  height: 0;
  margin-top: var(--q-space-3);
  border-radius: var(--q-radius-md);
  background: var(--q-primary);
  opacity: 0.35;
  transition-property: height, opacity;
}

.demo-panel.open {
  height: 3rem;
  opacity: 1;
}
</style>
