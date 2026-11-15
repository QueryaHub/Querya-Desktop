<script setup lang="ts">
import { computed, onMounted, onUnmounted } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { storeToRefs } from "pinia";
import { useShellStore } from "./stores/shell";
import { useShellStatusStore } from "./stores/shellStatus";
import { useConnectionsStore } from "./stores/connections";
import { useShellNavStore } from "./stores/shellNav";
import { initTheme } from "./theme/queryaTheme";
import { provideQueryaMotion } from "./motion";
import TitleBar from "./ui/TitleBar.vue";
import ConnectionsPanel from "./ui/ConnectionsPanel.vue";
import StatusBar from "./ui/StatusBar.vue";
import WorkspaceEmptyHero from "./ui/WorkspaceEmptyHero.vue";
import QueryaDivider from "./ui/QueryaDivider.vue";
import ConnectionHome from "./ui/ConnectionHome.vue";
import TableObjectView from "./ui/TableObjectView.vue";

const shell = useShellStore();
const status = useShellStatusStore();
const connections = useConnectionsStore();
const nav = useShellNavStore();
const { surface } = storeToRefs(nav);
provideQueryaMotion();

const showEmpty = computed(() => surface.value === "empty");
const showHome = computed(() => surface.value === "connectionHome");
const showTable = computed(() => surface.value === "tableObject");

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
    await connections.connectSqlite(selected);
  } catch (err) {
    if (String(err).includes("cancel")) return;
  }
}

function onNewConnection() {
  status.setQueryMetrics({
    message: "Connection form UI next — use Demo or Open SQLite for now",
    busy: false,
  });
}

function onLaunchDemo() {
  connections.launchDemo();
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
      message: `${info.name} ${info.version} · UI core · ${info.stack}${info.os ? ` · ${info.os}` : ""}`,
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
        <div class="workspace-body">
          <WorkspaceEmptyHero
            v-if="showEmpty"
            @new-connection="onNewConnection"
            @open-sqlite="onOpenSqlite"
            @launch-demo="onLaunchDemo"
            @open-tour="onOpenTour"
          />
          <ConnectionHome v-else-if="showHome" />
          <TableObjectView v-else-if="showTable" />
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
</style>
