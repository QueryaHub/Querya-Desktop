<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { storeToRefs } from "pinia";
import { useShellStore } from "./stores/shell";
import { useWorkspaceStore } from "./stores/workspace";
import {
  applyTheme,
  initTheme,
  type QueryaThemeMode,
} from "./theme/queryaTheme";
import {
  provideQueryaMotion,
  type QueryaMotionLevel,
} from "./motion";
import QueryaGlass from "./ui/QueryaGlass.vue";
import TitleBar from "./ui/TitleBar.vue";
import SidebarShell from "./ui/SidebarShell.vue";
import TabStrip from "./ui/TabStrip.vue";

const shell = useShellStore();
const workspace = useWorkspaceStore();
const { activeTab } = storeToRefs(workspace);
const motion = provideQueryaMotion();
const { level: motionLevel, springsOn, manual: motionManual } = motion;
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
  <div class="app-frame">
    <TitleBar />
    <div class="body">
      <SidebarShell />
      <main class="workspace">
        <TabStrip />
      <div class="hero">
        <header class="brand">Querya</header>
        <p class="tagline">
          Active tab: {{ activeTab?.title ?? "—" }} ({{ activeTab?.kind }})
        </p>
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
            :class="{ active: !motionManual }"
            @click="motion.followSystem()"
          >
            System
          </button>
          <button
            type="button"
            class="btn"
            :class="{ active: motionManual && motionLevel === 'full' }"
            @click="setMotion('full')"
          >
            Full
          </button>
          <button
            type="button"
            class="btn"
            :class="{ active: motionManual && motionLevel === 'reduced' }"
            @click="setMotion('reduced')"
          >
            Reduced
          </button>
          <button
            type="button"
            class="btn"
            :class="{ active: motionManual && motionLevel === 'off' }"
            @click="setMotion('off')"
          >
            Off
          </button>
        </div>

        <button
          type="button"
          class="btn demo-toggle"
          @click="panelOpen = !panelOpen"
        >
          Toggle demo panel
        </button>
        <div
          class="demo-panel"
          :class="{ open: panelOpen }"
          :style="panelStyle"
          data-testid="motion-demo-panel"
        />

        <QueryaGlass class="glass-demo" data-testid="glass-demo">
          <p class="glass-title">Liquid Glass</p>
          <p class="glass-copy">
            Drag the title bar · minimize / maximize / close on the chrome
          </p>
        </QueryaGlass>
      </div>
      </main>
    </div>
  </div>
</template>

<style scoped>
.app-frame {
  height: 100%;
  min-height: 100%;
  display: flex;
  flex-direction: column;
  background: var(--q-background);
  color: var(--q-foreground);
}

.body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: row;
}

.workspace {
  flex: 1;
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.hero {
  flex: 1;
  min-height: 0;
  overflow: auto;
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

.glass-demo {
  margin-top: var(--q-space-6);
  padding: var(--q-space-4) var(--q-space-6);
  max-width: 22rem;
  text-align: left;
}

.glass-title {
  margin: 0;
  font-weight: 600;
  color: var(--q-foreground);
}

.glass-copy {
  margin: var(--q-space-1) 0 0;
  font-size: var(--q-text-sm);
  color: var(--q-muted-foreground);
}
</style>
