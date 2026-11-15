import { defineStore } from "pinia";
import { reactive, ref } from "vue";
import {
  dbConnectSqlite,
  dbDisconnect,
  formatConnectionError,
} from "../api/connection";
import { DEMO_CONNECTION } from "../mock/demoCatalog";
import { useFoldersStore } from "./folders";
import { useShellNavStore } from "./shellNav";
import { useShellStatusStore } from "./shellStatus";

export type LiveConnection = {
  id: string;
  driver: "sqlite";
  name: string;
  path: string;
  /** Offline UI demo — no Rust session. */
  mock?: boolean;
  /** Optional SERVERS folder id. */
  folderId?: string | null;
};

function fileName(path: string): string {
  const parts = path.split(/[/\\]/);
  return parts[parts.length - 1] || path;
}

/** Saved / live sessions shown in SERVERS (Flutter connections list). */
export const useConnectionsStore = defineStore("connections", () => {
  const items = ref<LiveConnection[]>([]);
  /** Incremental index — not rebuilt on every upsert. */
  const byId = reactive(new Map<string, LiveConnection>());

  function upsert(conn: LiveConnection) {
    const list = items.value;
    const i = list.findIndex((c) => c.id === conn.id);
    if (i >= 0) list[i] = conn;
    else list.push(conn);
    byId.set(conn.id, conn);
  }

  function remove(id: string) {
    byId.delete(id);
    const list = items.value;
    const i = list.findIndex((c) => c.id === id);
    if (i >= 0) list.splice(i, 1);
  }

  /** Flutter-style Demo — full UI without opening a real file. */
  function launchDemo() {
    const nav = useShellNavStore();
    const status = useShellStatusStore();
    const folders = useFoldersStore();
    const samples = folders.ensureDemoFolder();
    const conn: LiveConnection = {
      id: DEMO_CONNECTION.id,
      driver: "sqlite",
      name: DEMO_CONNECTION.name,
      path: DEMO_CONNECTION.path,
      mock: true,
      folderId: samples.id,
    };
    upsert(conn);
    folders.setExpanded(samples.id, true);
    nav.setExpanded(conn.id, true);
    nav.selectConnection(conn.id);
    status.setConnection(conn.name, "Demo (offline)");
    status.setQueryMetrics({
      message: "Demo catalog · UI core (no live DB)",
      busy: false,
    });
    return conn;
  }

  async function connectSqlite(
    path: string,
    opts?: { folderId?: string | null; name?: string },
  ) {
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
        name: opts?.name?.trim() || fileName(path),
        path,
        folderId: opts?.folderId ?? null,
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
    const conn = byId.get(id);
    try {
      if (conn && !conn.mock) await dbDisconnect(id);
    } finally {
      remove(id);
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
    const conn = byId.get(id);
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

  function moveToFolder(connectionId: string, folderId: string | null) {
    const conn = byId.get(connectionId);
    if (!conn) return;
    conn.folderId = folderId;
  }

  /** Detach all connections from a folder (Flutter: folder delete keeps connections). */
  function detachFolder(folderId: string) {
    for (const c of items.value) {
      if (c.folderId === folderId) c.folderId = null;
    }
  }

  return {
    items,
    byId,
    launchDemo,
    connectSqlite,
    disconnect,
    select,
    moveToFolder,
    detachFolder,
  };
});
