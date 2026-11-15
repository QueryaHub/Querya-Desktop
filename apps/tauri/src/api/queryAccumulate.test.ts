import { describe, expect, it } from "vitest";
import { applyQueryEvent, emptyAccumulatedQuery } from "./queryAccumulate";

describe("applyQueryEvent (SQLite slice smoke)", () => {
  it("accumulates columns then batched rows then done", () => {
    let state = emptyAccumulatedQuery();
    state = applyQueryEvent(state, {
      type: "columns",
      names: ["id", "email"],
    });
    state = applyQueryEvent(state, {
      type: "rows",
      rows: [[1, "a@ex.com"]],
      offset: 0,
    });
    state = applyQueryEvent(state, {
      type: "rows",
      rows: [[2, "b@ex.com"]],
      offset: 1,
    });
    state = applyQueryEvent(state, {
      type: "done",
      row_count: 2,
      truncated: false,
      elapsed_ms: 3,
    });

    expect(state.columns).toEqual(["id", "email"]);
    expect(state.rows).toHaveLength(2);
    expect(state.rowCount).toBe(2);
    expect(state.truncated).toBe(false);
    expect(state.elapsedMs).toBe(3);
    expect(state.error).toBeNull();
  });
});
