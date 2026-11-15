import { createPinia, setActivePinia } from "pinia";
import { beforeEach, describe, expect, it } from "vitest";
import { useGridStagingStore } from "./gridStaging";

describe("useGridStagingStore", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it("attaches baseline and tracks dirty cell markers", () => {
    const store = useGridStagingStore();
    store.attachFromQuery(
      ["id", "name"],
      [
        ["1", "Alice"],
        ["2", "Bob"],
      ],
    );
    expect(store.isDirty).toBe(false);
    expect(store.cellStatus(0, 1)).toBe("clean");

    store.setCell(0, 1, "Alice Cooper");
    expect(store.isDirty).toBe(true);
    expect(store.changeCount).toBe(1);
    expect(store.cellStatus(0, 1)).toBe("modified");
    expect(store.rowStatus(0)).toBe("modified");
    expect(store.getCellValue(0, 1)).toBe("Alice Cooper");
    expect(store.effectiveRows()[0]?.[1]).toBe("Alice Cooper");
  });

  it("replaceBaseline clears prior edits", () => {
    const store = useGridStagingStore();
    store.attachFromQuery(["id"], [["1"]]);
    store.setCell(0, 0, "9");
    expect(store.isDirty).toBe(true);
    store.attachFromQuery(["id"], [["2"]]);
    expect(store.isDirty).toBe(false);
    expect(store.getCellValue(0, 0)).toBe("2");
  });

  it("revertAll discards dirty markers", () => {
    const store = useGridStagingStore();
    store.setTarget({
      connectionId: "c1",
      tableName: "users",
      primaryKeys: ["id"],
    });
    store.attachFromQuery(["id", "name"], [["1", "A"]]);
    store.setCell(0, 1, "B");
    expect(store.isDirty).toBe(true);
    expect(store.canApply).toBe(true);
    store.revertAll();
    expect(store.isDirty).toBe(false);
    expect(store.getCellValue(0, 1)).toBe("A");
  });
});
