import { defineStore } from "pinia";
import { computed, ref } from "vue";
import {
  dbConnectSqlite,
  dbDisconnect,
  formatConnectionError,
} from "../api/connection";
import { useShellStatusStore } from "./shellStatus";

export type LiveConnection = {
  id: string;
  driver: "sqlite";
  name: string;
  path: string;
};

function fileName(path: string): string {
  const parts = path.split(/[/\\]/);
  return parts[parts.length - 1] || path;
}

/** Live DB sessions opened in this app process. */
export const useConnectionsStore = defineStore("connections", () => {
  const items = ref<LiveConnection[]>([]);
  const activeId = ref<string | null>(null);

  const active = computed(
    () => items.value.find((c) => c.id === activeId.value) ?? null,
  );

  async function connectSqlite(path: string) {
    const status = useShellStatusStore();
    status.setQueryMetrics({ busy: true, message: `Opening ${fileName(path)}…` });
    try {
      const id = await dbConnectSqlite(path);
      const conn: LiveConnection = {
        id,
        driver: "sqlite",
        name: fileName(path),
        path,
      };
      items.value = [...items.value, conn];
      activeId.value = id;
      status.setConnection(conn.name, path);
      status.setQueryMetrics({
        busy: false,
        message: `Connected · ${conn.name}`,
      });
      return conn;
    } catch (err) {
      const msg = formatConnectionError(err);
      status.setQueryMetrics({ busy: false, message: msg });
      throw err;
    }
  }

  async function disconnect(id: string) {
    const status = useShellStatusStore();
    try {
      await dbDisconnect(id);
    } finally {
      items.value = items.value.filter((c) => c.id !== id);
      if (activeId.value === id) {
        activeId.value = items.value[0]?.id ?? null;
        const next = active.value;
        status.setConnection(next?.name ?? null, next?.path ?? null);
        status.setQueryMetrics({
          message: next ? `Connected · ${next.name}` : "Disconnected",
          busy: false,
        });
      }
    }
  }

  function select(id: string) {
    const conn = items.value.find((c) => c.id === id);
    if (!conn) return;
    activeId.value = id;
    const status = useShellStatusStore();
    status.setConnection(conn.name, conn.path);
    status.setQueryMetrics({ message: `Connected · ${conn.name}`, busy: false });
  }

  return { items, activeId, active, connectSqlite, disconnect, select };
});
