import { defineStore } from "pinia";
import { reactive, ref } from "vue";
import {
  dbDisconnect,
  formatConnectionError,
  profilesConnectSqlite,
  profilesDelete,
  profilesList,
  profilesUpsert,
  type ConnectionProfile,
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
  /** Live rusqlite session open in the registry. */
  connected?: boolean;
};

function fileName(path: string): string {
  const parts = path.split(/[/\\]/);
  return parts[parts.length - 1] || path;
}

function fromProfile(p: ConnectionProfile, connected = false): LiveConnection | null {
  if (p.driver !== "sqlite") return null;
  const path = p.path?.trim();
  if (!path) return null;
  return {
    id: p.id,
    driver: "sqlite",
    name: p.name,
    path,
    folderId: p.folder_id ?? null,
    connected,
  };
}

function toProfile(conn: LiveConnection): ConnectionProfile {
  const now = String(Math.floor(Date.now() / 1000));
  return {
    id: conn.id,
    driver: "sqlite",
    name: conn.name,
    path: conn.path,
    folder_id: conn.folderId ?? null,
    sort_order: 0,
    created_at: now,
    updated_at: now,
  };
}

/** Saved / live sessions shown in SERVERS (Flutter connections list). */
export const useConnectionsStore = defineStore("connections", () => {
  const items = ref<LiveConnection[]>([]);
  /** Incremental index — not rebuilt on every upsert. */
  const byId = reactive(new Map<string, LiveConnection>());
  const hydrated = ref(false);

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

  /** Load saved profiles into SERVERS (not connected until ensureConnected). */
  async function hydrate() {
    if (hydrated.value) return;
    const status = useShellStatusStore();
    try {
      const profiles = await profilesList();
      for (const p of profiles) {
        const conn = fromProfile(p, false);
        if (conn && !byId.has(conn.id)) upsert(conn);
      }
      hydrated.value = true;
      if (items.value.length > 0) {
        status.setQueryMetrics({
          message: `${items.value.length} saved connection${items.value.length === 1 ? "" : "s"}`,
          busy: false,
        });
      }
    } catch (err) {
      status.setQueryMetrics({
        message: formatConnectionError(err),
        busy: false,
      });
    }
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
      connected: true,
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
    opts?: { folderId?: string | null; name?: string; id?: string | null },
  ) {
    const status = useShellStatusStore();
    const nav = useShellNavStore();
    const name = opts?.name?.trim() || fileName(path);
    status.setQueryMetrics({
      busy: true,
      message: `Opening ${fileName(path)}…`,
    });
    try {
      const profile = await profilesConnectSqlite({
        name,
        path,
        folderId: opts?.folderId ?? null,
        id: opts?.id ?? null,
      });
      const conn: LiveConnection = {
        id: profile.id,
        driver: "sqlite",
        name: profile.name,
        path: profile.path ?? path,
        folderId: profile.folder_id ?? opts?.folderId ?? null,
        connected: true,
      };
      upsert(conn);
      nav.setExpanded(conn.id, true);
      nav.selectConnection(conn.id);
      status.setConnection(conn.name, conn.path);
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

  /** Open live session for a saved (or already listed) profile. */
  async function ensureConnected(id: string) {
    const conn = byId.get(id);
    if (!conn || conn.mock) return conn ?? null;
    if (conn.connected) return conn;
    return connectSqlite(conn.path, {
      name: conn.name,
      folderId: conn.folderId,
      id: conn.id,
    });
  }

  async function disconnect(id: string) {
    const status = useShellStatusStore();
    const nav = useShellNavStore();
    const conn = byId.get(id);
    try {
      if (conn && !conn.mock && conn.connected) await dbDisconnect(id);
    } finally {
      if (conn && !conn.mock) {
        conn.connected = false;
        byId.set(id, conn);
      } else {
        remove(id);
      }
      if (nav.selectedConnectionId === id) {
        status.setConnection(conn?.name ?? null, conn?.path ?? null);
        status.setQueryMetrics({
          message: conn ? `Disconnected · ${conn.name}` : "No connection",
          busy: false,
        });
      }
    }
  }

  /** Remove from SERVERS + LocalDb (Flutter "Remove connection"). */
  async function removeConnection(id: string) {
    const status = useShellStatusStore();
    const nav = useShellNavStore();
    const conn = byId.get(id);
    try {
      if (conn && !conn.mock) {
        if (conn.connected) {
          try {
            await dbDisconnect(id);
          } catch {
            /* already closed */
          }
        }
        await profilesDelete(id);
      }
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

  async function select(id: string) {
    const nav = useShellNavStore();
    const status = useShellStatusStore();
    let conn = byId.get(id);
    if (!conn) return;
    if (!conn.mock && !conn.connected) {
      try {
        conn = (await ensureConnected(id)) ?? conn;
      } catch {
        return;
      }
    }
    nav.selectConnection(id);
    status.setConnection(conn.name, conn.mock ? "Demo (offline)" : conn.path);
    status.setQueryMetrics({
      message: conn.mock
        ? "Demo catalog · UI core (no live DB)"
        : `Connected · ${conn.name}`,
      busy: false,
    });
  }

  async function moveToFolder(connectionId: string, folderId: string | null) {
    const conn = byId.get(connectionId);
    if (!conn) return;
    conn.folderId = folderId;
    byId.set(connectionId, conn);
    if (conn.mock) return;
    try {
      await profilesUpsert(toProfile(conn));
    } catch (err) {
      const status = useShellStatusStore();
      status.setQueryMetrics({
        message: formatConnectionError(err),
        busy: false,
      });
    }
  }

  /** Detach all connections from a folder (Flutter: folder delete keeps connections). */
  function detachFolder(folderId: string) {
    for (const c of items.value) {
      if (c.folderId === folderId) {
        c.folderId = null;
        if (!c.mock) void profilesUpsert(toProfile(c));
      }
    }
  }

  return {
    items,
    byId,
    hydrated,
    hydrate,
    launchDemo,
    connectSqlite,
    ensureConnected,
    disconnect,
    removeConnection,
    select,
    moveToFolder,
    detachFolder,
  };
});
