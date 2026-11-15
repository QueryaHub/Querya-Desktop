import type { QueryEvent } from "./query";

export type AccumulatedQuery = {
  columns: string[];
  rows: unknown[][];
  rowCount: number;
  truncated: boolean;
  elapsedMs: number | null;
  affectedRows: number | null;
  error: string | null;
};

export function emptyAccumulatedQuery(): AccumulatedQuery {
  return {
    columns: [],
    rows: [],
    rowCount: 0,
    truncated: false,
    elapsedMs: null,
    affectedRows: null,
    error: null,
  };
}

/**
 * Mutating reducer — appends row batches in place (no full-array concat).
 * Callers must treat `state.rows` as the durable buffer across events.
 */
export function applyQueryEvent(
  state: AccumulatedQuery,
  ev: QueryEvent,
): AccumulatedQuery {
  switch (ev.type) {
    case "columns":
      state.columns = ev.names;
      state.rows.length = 0;
      state.rowCount = 0;
      state.truncated = false;
      state.elapsedMs = null;
      state.affectedRows = null;
      state.error = null;
      return state;
    case "rows": {
      // Append batch only — do not copy prior rows (was O(n²) via concat).
      const rows = state.rows;
      const batch = ev.rows;
      for (let i = 0; i < batch.length; i++) rows.push(batch[i]!);
      return state;
    }
    case "done":
      state.rowCount = ev.row_count;
      state.truncated = ev.truncated;
      state.elapsedMs = ev.elapsed_ms;
      state.affectedRows =
        ev.affected_rows === undefined || ev.affected_rows === null
          ? null
          : ev.affected_rows;
      return state;
    case "error":
      state.error = ev.message;
      return state;
  }
}
