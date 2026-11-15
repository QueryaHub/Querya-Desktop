import { describe, expect, it } from "vitest";
import { NULL_SENTINEL, StagingBuffer } from "./buffer";

describe("StagingBuffer (frontend)", () => {
  function sample() {
    return new StagingBuffer(
      ["id", "name", "email"],
      [
        ["1", "Alice", "alice@test.com"],
        ["2", "Bob", "bob@test.com"],
      ],
      ["id"],
    );
  }

  it("starts clean", () => {
    const buf = sample();
    expect(buf.isDirty()).toBe(false);
    expect(buf.cellStatus(0, 1)).toBe("clean");
    expect(buf.getCellValue(0, 1)).toBe("Alice");
  });

  it("marks cell dirty and clears when reverted to original", () => {
    const buf = sample();
    buf.setCell(0, 1, "Alice Cooper");
    expect(buf.isDirty()).toBe(true);
    expect(buf.cellStatus(0, 1)).toBe("modified");
    expect(buf.rowStatus(0)).toBe("modified");
    expect(buf.getCellValue(0, 1)).toBe("Alice Cooper");
    buf.setCell(0, 1, "Alice");
    expect(buf.isDirty()).toBe(false);
    expect(buf.cellStatus(0, 1)).toBe("clean");
  });

  it("toggle delete and null sentinel", () => {
    const buf = sample();
    buf.toggleDeleteRow(1);
    expect(buf.rowStatus(1)).toBe("deleted");
    buf.setCellNull(0, 2);
    expect(buf.getCellValue(0, 2)).toBe("NULL");
    expect(buf.effectiveRows()[0]?.[2]).toBe("NULL");
    expect(NULL_SENTINEL).toContain("QUERYA_NULL");
  });

  it("addRow and toApplySnapshot", () => {
    const buf = sample();
    buf.setCell(0, 1, "Alicia");
    buf.addRow(["3", "Carol", "carol@test.com"]);
    const snap = buf.toApplySnapshot();
    expect(snap.modifiedCells).toEqual([
      { row: 0, col: 1, value: "Alicia" },
    ]);
    expect(snap.insertedRows).toHaveLength(1);
    expect(snap.primaryKeys).toEqual(["id"]);
  });
});
