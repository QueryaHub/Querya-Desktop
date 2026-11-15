import { defineStore } from "pinia";
import { ref, shallowRef } from "vue";
import { dbExecuteQuery, type QueryEvent } from "../api/query";
import {
  applyQueryEvent,
  emptyAccumulatedQuery,
} from "../api/queryAccumulate";
import {
  asConnectionError,
  formatConnectionError,
} from "../api/connection";
import { useConnectionsStore } from "./connections";
import { usePreferencesStore } from "./preferences";
import { useShellNavStore } from "./shellNav";
import { useShellStatusStore } from "./shellStatus";

/** Last streamed / browsed result — Glide grid binds here. */
export const useQueryResultStore = defineStore("queryResult", () => {
  let acc = emptyAccumulatedQuery();

  const columns = shallowRef<string[]>(acc.columns);
  /** Durable row buffer — mutated in place across batches. */
  const rows = shallowRef<unknown[][]>(acc.rows);
  /** Bumps on any result change so grids can shallow-watch without deep scan. */
  const revision = ref(0);
  const running = ref(false);
  const truncated = ref(false);
  const rowCount = ref(0);
  const elapsedMs = ref<number | null>(null);
  const affectedRows = ref<number | null>(null);
  const error = ref<string | null>(null);

  function bump() {
    revision.value += 1;
  }

  function bindBuffers() {
    columns.value = acc.columns;
    rows.value = acc.rows;
  }

  function syncScalars() {
    truncated.value = acc.truncated;
    rowCount.value = acc.rowCount || acc.rows.length;
    elapsedMs.value = acc.elapsedMs;
    affectedRows.value = acc.affectedRows;
    error.value = acc.error;
  }

  function reset() {
    acc = emptyAccumulatedQuery();
    bindBuffers();
    syncScalars();
    bump();
  }

  function feedEvent(ev: QueryEvent) {
    applyQueryEvent(acc, ev);
    if (ev.type === "columns") {
      bindBuffers();
    } else if (rows.value !== acc.rows) {
      rows.value = acc.rows;
    }
    if (ev.type === "rows") {
      // Interim count while streaming; `done` sets authoritative row_count.
      rowCount.value = acc.rows.length;
    } else {
      syncScalars();
    }
    if (ev.type === "error") error.value = acc.error;
    bump();
  }

  function setSnapshot(opts: {
    columns: string[];
    rows: unknown[][];
    message?: string;
  }) {
    acc = emptyAccumulatedQuery();
    acc.columns = opts.columns;
    acc.rows = opts.rows;
    acc.rowCount = opts.rows.length;
    acc.elapsedMs = 0;
    bindBuffers();
    syncScalars();
    bump();
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
      const prefs = usePreferencesStore();
      // Pref off → skip dialog and send confirmed on the first attempt.
      let confirmed = !prefs.state.confirmDestructive;
      try {
        await dbExecuteQuery(id, trimmed, feedEvent, { confirmed });
      } catch (err) {
        const needs = asConnectionError(err);
        if (needs?.kind !== "needs_confirmation" || confirmed) throw err;
        const ok = window.confirm(
          `${needs.message}\n\nRun this statement anyway?`,
        );
        if (!ok) {
          error.value = "Cancelled";
          status.setQueryMetrics({ message: error.value, busy: false });
          return;
        }
        confirmed = true;
        reset();
        await dbExecuteQuery(id, trimmed, feedEvent, { confirmed });
      }
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
    revision,
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
