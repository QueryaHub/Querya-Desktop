import { defineStore } from "pinia";
import { reactive, ref } from "vue";
import {
  dbDisconnect,
  formatConnectionError,
  profilesConnectPostgres,
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
  driver: "sqlite" | "postgres";
  name: string;
  /** SQLite file path. */
  path?: string;
  host?: string;
  port?: number;
  database?: string;
  user?: string;
  /** Offline UI demo — no Rust session. */
  mock?: boolean;
  /** Optional SERVERS folder id. */
  folderId?: string | null;
  /** Live session open in the registry. */
  connected?: boolean;
};

/** Session-only passwords — never written to ProfileStore (keyring: #1878). */
const sessionPasswords = reactive(new Map<string, string>());

function fileName(path: string): string {
  const parts = path.split(/[/\\]/);
  return parts[parts.length - 1] || path;
}

function endpointLabel(conn: LiveConnection): string {
  if (conn.mock) return "Demo (offline)";
  if (conn.driver === "sqlite") return conn.path ?? "";
  const host = conn.host ?? "localhost";
  const port = conn.port ?? 5432;
  const db = conn.database ?? "";
  return `${host}:${port}/${db}`;
}

function fromProfile(p: ConnectionProfile, connected = false): LiveConnection | null {
  if (p.driver === "sqlite") {
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
  if (p.driver === "postgres") {
    const host = p.host?.trim();
    const database = p.database_name?.trim();
    const user = p.username?.trim();
    if (!host || !database || !user) return null;
    return {
      id: p.id,
      driver: "postgres",
      name: p.name,
      host,
      port: p.port != null ? Number(p.port) : 5432,
      database,
      user,
      folderId: p.folder_id ?? null,
      connected,
    };
  }
  return null;
}

function toProfile(conn: LiveConnection): ConnectionProfile {
  const now = String(Math.floor(Date.now() / 1000));
  if (conn.driver === "postgres") {
    return {
      id: conn.id,
      driver: "postgres",
      name: conn.name,
      host: conn.host ?? null,
      port: conn.port ?? 5432,
      username: conn.user ?? null,
      database_name: conn.database ?? null,
      folder_id: conn.folderId ?? null,
      sort_order: 0,
      created_at: now,
      updated_at: now,
    };
  }
  return {
    id: conn.id,
    driver: "sqlite",
    name: conn.name,
    path: conn.path ?? null,
    folder_id: conn.folderId ?? null,
    sort_order: 0,
    created_at: now,
    updated_at: now,
  };
}

/** Saved / live sessions shown in SERVERS (Flutter connections list). */
export const useConnectionsStore = defineStore("connections", () => {
  const items = ref<LiveConnection[]>([]);
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
    sessionPasswords.delete(id);
    const list = items.value;
    const i = list.findIndex((c) => c.id === id);
    if (i >= 0) list.splice(i, 1);
  }

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
      status.setConnection(conn.name, conn.path ?? path);
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

  async function connectPostgres(opts: {
    name: string;
    host: string;
    port: number;
    database: string;
    user: string;
    password?: string | null;
    folderId?: string | null;
    id?: string | null;
  }) {
    const status = useShellStatusStore();
    const nav = useShellNavStore();
    const name =
      opts.name.trim() ||
      `${opts.user}@${opts.host}/${opts.database}`;
    status.setQueryMetrics({
      busy: true,
      message: `Connecting ${opts.host}:${opts.port}…`,
    });
    try {
      const profile = await profilesConnectPostgres({
        name,
        host: opts.host,
        port: opts.port,
        database: opts.database,
        user: opts.user,
        password: opts.password ?? null,
        folderId: opts.folderId ?? null,
        id: opts.id ?? null,
      });
      if (opts.password) sessionPasswords.set(profile.id, opts.password);
      const conn: LiveConnection = {
        id: profile.id,
        driver: "postgres",
        name: profile.name,
        host: profile.host ?? opts.host,
        port: profile.port != null ? Number(profile.port) : opts.port,
        database: profile.database_name ?? opts.database,
        user: profile.username ?? opts.user,
        folderId: profile.folder_id ?? opts.folderId ?? null,
        connected: true,
      };
      upsert(conn);
      nav.setExpanded(conn.id, true);
      nav.selectConnection(conn.id);
      status.setConnection(conn.name, endpointLabel(conn));
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

  async function ensureConnected(id: string) {
    const conn = byId.get(id);
    if (!conn || conn.mock) return conn ?? null;
    if (conn.connected) return conn;
    if (conn.driver === "sqlite") {
      return connectSqlite(conn.path ?? "", {
        name: conn.name,
        folderId: conn.folderId,
        id: conn.id,
      });
    }
    // Prefer in-memory cache; otherwise Rust loads from OS keyring (#1878).
    const password = sessionPasswords.get(id) ?? null;
    return connectPostgres({
      name: conn.name,
      host: conn.host ?? "localhost",
      port: conn.port ?? 5432,
      database: conn.database ?? "postgres",
      user: conn.user ?? "postgres",
      password,
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
        status.setConnection(conn?.name ?? null, conn ? endpointLabel(conn) : null);
        status.setQueryMetrics({
          message: conn ? `Disconnected · ${conn.name}` : "No connection",
          busy: false,
        });
      }
    }
  }

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
        status.setConnection(
          next?.name ?? null,
          next ? endpointLabel(next) : null,
        );
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
        // Still select so Overview/SQL are reachable; PG may need re-auth.
        nav.selectConnection(id);
        status.setConnection(conn.name, endpointLabel(conn));
        return;
      }
    }
    nav.selectConnection(id);
    status.setConnection(conn.name, endpointLabel(conn));
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
    connectPostgres,
    ensureConnected,
    disconnect,
    removeConnection,
    select,
    moveToFolder,
    detachFolder,
  };
});
