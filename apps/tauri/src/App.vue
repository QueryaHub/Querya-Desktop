<script setup lang="ts">
import { computed, onMounted, onUnmounted } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { storeToRefs } from "pinia";
import { useShellStore } from "./stores/shell";
import { useShellStatusStore } from "./stores/shellStatus";
import { useWorkspaceStore } from "./stores/workspace";
import { useConnectionsStore } from "./stores/connections";
import { initTheme } from "./theme/queryaTheme";
import { provideQueryaMotion } from "./motion";
import TitleBar from "./ui/TitleBar.vue";
import ConnectionsPanel from "./ui/ConnectionsPanel.vue";
import TabStrip from "./ui/TabStrip.vue";
import StatusBar from "./ui/StatusBar.vue";
import WorkspaceEmptyHero from "./ui/WorkspaceEmptyHero.vue";
import QueryaDivider from "./ui/QueryaDivider.vue";
import SqlWorkspace from "./ui/SqlWorkspace.vue";

const shell = useShellStore();
const status = useShellStatusStore();
const workspace = useWorkspaceStore();
const connections = useConnectionsStore();
const { activeTab } = storeToRefs(workspace);
provideQueryaMotion();

const showEmpty = computed(
  () => !connections.active && activeTab.value?.kind === "welcome",
);

const showSql = computed(() => activeTab.value?.kind === "sql");

async function onOpenSqlite() {
  try {
    const selected = await open({
      multiple: false,
      directory: false,
      title: "Open SQLite database",
      filters: [
        { name: "SQLite", extensions: ["db", "sqlite", "sqlite3"] },
        { name: "All files", extensions: ["*"] },
      ],
    });
    if (!selected || Array.isArray(selected)) return;
    const conn = await connections.connectSqlite(selected);
    workspace.addTab({ title: conn.name, kind: "sql" });
  } catch (err) {
    if (String(err).includes("cancel")) return;
  }
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
          <SqlWorkspace v-else-if="showSql" />
          <div v-else class="tab-placeholder" data-testid="tab-placeholder">
            <h2>{{ activeTab?.title }}</h2>
            <p v-if="connections.active">
              Connected: {{ connections.active.path }}
            </p>
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
  overflow: hidden;
  display: flex;
  flex-direction: column;
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
