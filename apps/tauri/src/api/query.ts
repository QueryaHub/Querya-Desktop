import { Channel, invoke } from "@tauri-apps/api/core";

export type QueryEvent =
  | { type: "columns"; names: string[] }
  | { type: "rows"; rows: unknown[][]; offset: number }
  | {
      type: "done";
      row_count: number;
      truncated: boolean;
      affected_rows?: number | null;
      elapsed_ms: number;
    }
  | { type: "error"; message: string };

export type QueryEventHandler = (event: QueryEvent) => void;

/** Stream SQL results over a Tauri Channel. */
export async function dbExecuteQuery(
  id: string,
  sql: string,
  onEvent: QueryEventHandler,
  opts?: { limit?: number; confirmed?: boolean },
): Promise<void> {
  const channel = new Channel<QueryEvent>();
  channel.onmessage = onEvent;
  await invoke("db_execute_query", {
    id,
    sql,
    limit: opts?.limit ?? null,
    confirmed: opts?.confirmed ?? false,
    onEvent: channel,
  });
}
