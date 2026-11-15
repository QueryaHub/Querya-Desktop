import { defineStore } from "pinia";
import { computed, ref } from "vue";
import {
  dbConnectSqlite,
  dbDisconnect,
  formatConnectionError,
} from "../api/connection";
import { DEMO_CONNECTION } from "../mock/demoCatalog";
import { useShellNavStore } from "./shellNav";
import { useShellStatusStore } from "./shellStatus";

export type LiveConnection = {
  id: string;
  driver: "sqlite";
  name: string;
  path: string;
  /** Offline UI demo — no Rust session. */
  mock?: boolean;
};

function fileName(path: string): string {
  const parts = path.split(/[/\\]/);
  return parts[parts.length - 1] || path;
}

/** Saved / live sessions shown in SERVERS (Flutter connections list). */
export const useConnectionsStore = defineStore("connections", () => {
  const items = ref<LiveConnection[]>([]);

  const byId = computed(() => {
    const map = new Map<string, LiveConnection>();
    for (const c of items.value) map.set(c.id, c);
    return map;
  });

  function upsert(conn: LiveConnection) {
    const rest = items.value.filter((c) => c.id !== conn.id);
    items.value = [...rest, conn];
  }

  /** Flutter-style Demo — full UI without opening a real file. */
  function launchDemo() {
    const nav = useShellNavStore();
    const status = useShellStatusStore();
    const conn: LiveConnection = {
      id: DEMO_CONNECTION.id,
      driver: "sqlite",
      name: DEMO_CONNECTION.name,
      path: DEMO_CONNECTION.path,
      mock: true,
    };
    upsert(conn);
    nav.setExpanded(conn.id, true);
    nav.selectConnection(conn.id);
    status.setConnection(conn.name, "Demo (offline)");
    status.setQueryMetrics({
      message: "Demo catalog · UI core (no live DB)",
      busy: false,
    });
    return conn;
  }

  async function connectSqlite(path: string) {
    const status = useShellStatusStore();
    const nav = useShellNavStore();
    status.setQueryMetrics({
      busy: true,
      message: `Opening ${fileName(path)}…`,
    });
    try {
      const id = await dbConnectSqlite(path);
      const conn: LiveConnection = {
        id,
        driver: "sqlite",
        name: fileName(path),
        path,
      };
      upsert(conn);
      nav.setExpanded(id, true);
      nav.selectConnection(id);
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
    const nav = useShellNavStore();
    const conn = byId.value.get(id);
    try {
      if (conn && !conn.mock) await dbDisconnect(id);
    } finally {
      items.value = items.value.filter((c) => c.id !== id);
      if (nav.selectedConnectionId === id) {
        const next = items.value[0] ?? null;
        if (next) nav.selectConnection(next.id);
        else nav.reset();
        status.setConnection(next?.name ?? null, next?.path ?? null);
        status.setQueryMetrics({
          message: next ? `Connected · ${next.name}` : "No connection",
          busy: false,
        });
      }
    }
  }

  function select(id: string) {
    const conn = byId.value.get(id);
    if (!conn) return;
    const nav = useShellNavStore();
    const status = useShellStatusStore();
    nav.selectConnection(id);
    status.setConnection(conn.name, conn.mock ? "Demo (offline)" : conn.path);
    status.setQueryMetrics({
      message: conn.mock
        ? "Demo catalog · UI core (no live DB)"
        : `Connected · ${conn.name}`,
      busy: false,
    });
  }

  return {
    items,
    byId,
    launchDemo,
    connectSqlite,
    disconnect,
    select,
  };
});
