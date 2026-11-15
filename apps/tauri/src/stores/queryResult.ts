import { defineStore } from "pinia";
import { ref } from "vue";
import {
  dbExecuteQuery,
  type QueryEvent,
} from "../api/query";
import { formatConnectionError } from "../api/connection";
import { useConnectionsStore } from "./connections";
import { useShellStatusStore } from "./shellStatus";

/** Last streamed query result — grid (#1876) binds here. */
export const useQueryResultStore = defineStore("queryResult", () => {
  const columns = ref<string[]>([]);
  const rows = ref<unknown[][]>([]);
  const running = ref(false);
  const truncated = ref(false);
  const rowCount = ref(0);
  const elapsedMs = ref<number | null>(null);
  const affectedRows = ref<number | null>(null);
  const error = ref<string | null>(null);

  function reset() {
    columns.value = [];
    rows.value = [];
    truncated.value = false;
    rowCount.value = 0;
    elapsedMs.value = null;
    affectedRows.value = null;
    error.value = null;
  }

  function onEvent(ev: QueryEvent) {
    switch (ev.type) {
      case "columns":
        columns.value = ev.names;
        rows.value = [];
        break;
      case "rows":
        rows.value = rows.value.concat(ev.rows);
        break;
      case "done":
        rowCount.value = ev.row_count;
        truncated.value = ev.truncated;
        elapsedMs.value = ev.elapsed_ms;
        affectedRows.value =
          ev.affected_rows === undefined || ev.affected_rows === null
            ? null
            : ev.affected_rows;
        break;
      case "error":
        error.value = ev.message;
        break;
    }
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
