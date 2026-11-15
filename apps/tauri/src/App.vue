<script setup lang="ts">
import { computed, onMounted, onUnmounted } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { storeToRefs } from "pinia";
import { useShellStore } from "./stores/shell";
import { useShellStatusStore } from "./stores/shellStatus";
import { useWorkspaceStore } from "./stores/workspace";
import { initTheme } from "./theme/queryaTheme";
import { provideQueryaMotion } from "./motion";
import TitleBar from "./ui/TitleBar.vue";
import ConnectionsPanel from "./ui/ConnectionsPanel.vue";
import TabStrip from "./ui/TabStrip.vue";
import StatusBar from "./ui/StatusBar.vue";
import WorkspaceEmptyHero from "./ui/WorkspaceEmptyHero.vue";
import QueryaDivider from "./ui/QueryaDivider.vue";

const shell = useShellStore();
const status = useShellStatusStore();
const workspace = useWorkspaceStore();
const { activeTab } = storeToRefs(workspace);
provideQueryaMotion();

const showEmpty = computed(
  () => !status.connectionName && activeTab.value?.kind === "welcome",
);

function onOpenSqlite() {
  status.setQueryMetrics({
    message: "SQLite open will land with #1873",
    busy: false,
  });
  workspace.addTab({ title: "SQLite", kind: "sql" });
}

function onNewConnection() {
  status.setQueryMetrics({
    message: "Connection form will land with keyring/profiles",
    busy: false,
  });
}

function onOpenTour() {
  status.setQueryMetrics({ message: "Tour stub", busy: false });
}

function onKeydown(e: KeyboardEvent) {
  const mod = e.metaKey || e.ctrlKey;
  if (!mod) return;
  // Ctrl/Cmd+B — Flutter main_screen_shortcuts sidebar toggle
  if (e.key.toLowerCase() === "b") {
    e.preventDefault();
    shell.toggleSidebar();
  }
}

onMounted(async () => {
  initTheme();
  window.addEventListener("keydown", onKeydown);
  try {
    const info = await invoke<{
      name: string;
      stack: string;
      version: string;
      os?: string;
    }>("app_info");
    status.setQueryMetrics({
      message: `${info.name} ${info.version} · ${info.stack}${info.os ? ` · ${info.os}` : ""}`,
    });
  } catch {
    status.setQueryMetrics({ message: "IPC unavailable" });
  } finally {
    shell.markReady();
  }
});

onUnmounted(() => {
  window.removeEventListener("keydown", onKeydown);
});
</script>

<template>
  <div class="app-frame" data-testid="main-screen">
    <TitleBar />
    <QueryaDivider />
    <div class="body">
      <ConnectionsPanel
        @open-sqlite="onOpenSqlite"
        @new-connection="onNewConnection"
      />
      <main class="workspace">
        <TabStrip />
        <div class="workspace-body">
          <WorkspaceEmptyHero
            v-if="showEmpty"
            @new-connection="onNewConnection"
            @open-sqlite="onOpenSqlite"
            @open-tour="onOpenTour"
          />
          <div v-else class="tab-placeholder" data-testid="tab-placeholder">
            <h2>{{ activeTab?.title }}</h2>
            <p>Kind: {{ activeTab?.kind }} — editor/grid land in the SQLite slice.</p>
          </div>
        </div>
      </main>
    </div>
    <StatusBar />
  </div>
</template>

<style scoped>
.app-frame {
  height: 100%;
  min-height: 100%;
  display: flex;
  flex-direction: column;
  background: var(--q-canvas);
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
  background: var(--q-canvas);
}

.workspace-body {
  flex: 1;
  min-height: 0;
  overflow: auto;
}

.tab-placeholder {
  height: 100%;
  display: grid;
  place-content: center;
  justify-items: center;
  gap: var(--q-space-2);
  padding: var(--q-space-8);
  text-align: center;
  color: var(--q-muted-foreground);
}

.tab-placeholder h2 {
  margin: 0;
  color: var(--q-foreground);
  font-size: var(--q-text-lg);
}
</style>
