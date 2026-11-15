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

/** Pure reducer used by the queryResult store and smoke tests. */
export function applyQueryEvent(
  state: AccumulatedQuery,
  ev: QueryEvent,
): AccumulatedQuery {
  switch (ev.type) {
    case "columns":
      return {
        ...state,
        columns: ev.names,
        rows: [],
        error: null,
      };
    case "rows":
      return {
        ...state,
        rows: state.rows.concat(ev.rows),
      };
    case "done":
      return {
        ...state,
        rowCount: ev.row_count,
        truncated: ev.truncated,
        elapsedMs: ev.elapsed_ms,
        affectedRows:
          ev.affected_rows === undefined || ev.affected_rows === null
            ? null
            : ev.affected_rows,
      };
    case "error":
      return { ...state, error: ev.message };
  }
}
