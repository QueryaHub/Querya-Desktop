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
import { useShellStatusStore } from "./shellStatus";

/** Last streamed query result — Glide grid binds here. */
export const useQueryResultStore = defineStore("queryResult", () => {
  const columns = ref<string[]>([]);
  const rows = ref<unknown[][]>([]);
  const running = ref(false);
  const truncated = ref(false);
  const rowCount = ref(0);
  const elapsedMs = ref<number | null>(null);
  const affectedRows = ref<number | null>(null);
  const error = ref<string | null>(null);

  function syncFrom(acc: AccumulatedQuery) {
    columns.value = acc.columns;
    rows.value = acc.rows;
    truncated.value = acc.truncated;
    rowCount.value = acc.rowCount;
    elapsedMs.value = acc.elapsedMs;
    affectedRows.value = acc.affectedRows;
    error.value = acc.error;
  }

  function reset() {
    syncFrom(emptyAccumulatedQuery());
  }

  let acc = emptyAccumulatedQuery();

  function onEvent(ev: QueryEvent) {
    acc = applyQueryEvent(acc, ev);
    syncFrom(acc);
  }

  async function run(sql: string) {
    const connections = useConnectionsStore();
    const status = useShellStatusStore();
    const id = connections.activeId;
    if (!id) {
      error.value = "No active connection";
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
    acc = emptyAccumulatedQuery();
    running.value = true;
    status.setQueryMetrics({ message: "Running…", busy: true });
    try {
      await dbExecuteQuery(id, trimmed, onEvent);
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
    run,
  };
});
