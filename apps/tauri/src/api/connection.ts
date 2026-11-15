import { invoke } from "@tauri-apps/api/core";

export async function dbConnectSqlite(path: string): Promise<string> {
  return invoke<string>("db_connect_sqlite", { path });
}

export async function dbDisconnect(id: string): Promise<void> {
  await invoke("db_disconnect", { id });
}

export async function dbIsConnected(id: string): Promise<boolean> {
  return invoke<boolean>("db_is_connected", { id });
}

export function formatConnectionError(err: unknown): string {
  if (typeof err === "string") return err;
  if (err && typeof err === "object") {
    const e = err as Record<string, unknown>;
    if (typeof e.kind === "string") {
      const parts = [e.kind, e.driver, e.message, e.id]
        .filter((v): v is string => typeof v === "string" && v.length > 0);
      return parts.join(": ");
    }
    if (typeof e.message === "string") return e.message;
  }
  return String(err);
}
