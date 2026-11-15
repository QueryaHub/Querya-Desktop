import { defineStore } from "pinia";
import { ref } from "vue";
import { dbExecuteQuery, type QueryEvent } from "../api/query";
import {
  applyQueryEvent,
  emptyAccumulatedQuery,
  type AccumulatedQuery,
} from "../api/queryAccumulate";
import { formatConnectionError } from "../api/connection";
import { useConnectionsStore } from "./connections";
import { useShellNavStore } from "./shellNav";
import { useShellStatusStore } from "./shellStatus";

/** Last streamed / browsed result — Glide grid binds here. */
export const useQueryResultStore = defineStore("queryResult", () => {
  const columns = ref<string[]>([]);
  const rows = ref<unknown[][]>([]);
  const running = ref(false);
  const truncated = ref(false);
  const rowCount = ref(0);
  const elapsedMs = ref<number | null>(null);
  const affectedRows = ref<number | null>(null);
  const error = ref<string | null>(null);

  let acc = emptyAccumulatedQuery();

  function syncFrom(next: AccumulatedQuery) {
    columns.value = next.columns;
    rows.value = next.rows;
    truncated.value = next.truncated;
    rowCount.value = next.rowCount;
    elapsedMs.value = next.elapsedMs;
    affectedRows.value = next.affectedRows;
    error.value = next.error;
  }

  function reset() {
    acc = emptyAccumulatedQuery();
    syncFrom(acc);
  }

  function feedEvent(ev: QueryEvent) {
    acc = applyQueryEvent(acc, ev);
    syncFrom(acc);
  }

  function setSnapshot(opts: {
    columns: string[];
    rows: unknown[][];
    message?: string;
  }) {
    acc = {
      ...emptyAccumulatedQuery(),
      columns: opts.columns,
      rows: opts.rows,
      rowCount: opts.rows.length,
      elapsedMs: 0,
    };
    syncFrom(acc);
    if (opts.message) {
      useShellStatusStore().setQueryMetrics({
        message: opts.message,
        busy: false,
        rows: opts.rows.length,
        cols: opts.columns.length,
        durationMs: 0,
      });
    }
  }

  async function run(sql: string) {
    const connections = useConnectionsStore();
    const nav = useShellNavStore();
    const status = useShellStatusStore();
    const id = nav.selectedConnectionId;
    const conn = id ? connections.byId.get(id) : null;
    if (!id || !conn) {
      error.value = "No active connection";
      status.setQueryMetrics({ message: error.value, busy: false });
      return;
    }
    if (conn.mock) {
      error.value = "Demo connection — open a table from the sidebar for Data";
      status.setQueryMetrics({ message: error.value, busy: false });
      return;
    }
    const trimmed = sql.trim();
    if (!trimmed) {
      error.value = "SQL is empty";
      status.setQueryMetrics({ message: error.value, busy: false });
      return;
    }

    reset();
    running.value = true;
    status.setQueryMetrics({ message: "Running…", busy: true });
    try {
      await dbExecuteQuery(id, trimmed, feedEvent);
      if (error.value) {
        status.setQueryMetrics({ message: error.value, busy: false });
      } else if (affectedRows.value != null && columns.value.length === 0) {
        status.setQueryMetrics({
          message: `${affectedRows.value} rows affected · ${elapsedMs.value ?? 0} ms`,
          busy: false,
          rows: affectedRows.value,
          cols: 0,
          durationMs: elapsedMs.value,
        });
      } else {
        const trunc = truncated.value ? " (truncated)" : "";
        status.setQueryMetrics({
          message: `${rowCount.value} rows · ${columns.value.length} cols · ${elapsedMs.value ?? 0} ms${trunc}`,
          busy: false,
          rows: rowCount.value,
          cols: columns.value.length,
          durationMs: elapsedMs.value,
        });
      }
    } catch (err) {
      const msg = formatConnectionError(err);
      error.value = error.value ?? msg;
      status.setQueryMetrics({ message: error.value, busy: false });
    } finally {
      running.value = false;
    }
  }

  return {
    columns,
    rows,
    running,
    truncated,
    rowCount,
    elapsedMs,
    affectedRows,
    error,
    reset,
    feedEvent,
    setSnapshot,
    run,
  };
});
