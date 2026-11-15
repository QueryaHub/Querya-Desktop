import { describe, expect, it } from "vitest";
import { ROW_MARKER_WIDTH, sizeGlideColumns } from "./columnWidths";

describe("sizeGlideColumns", () => {
  it("sets grow when viewport has spare width", () => {
    const cols = sizeGlideColumns({
      columns: ["id", "name"],
      rows: [[1, "a"]],
      viewportWidth: 1200,
    });
    expect(cols).toHaveLength(2);
    expect(cols.every((c) => c.grow === 1)).toBe(true);
    const total = cols.reduce((s, c) => s + c.width, 0);
    expect(total).toBeLessThan(1200 - ROW_MARKER_WIDTH);
  });

  it("skips grow when content already fills the viewport", () => {
    const wide = "x".repeat(80);
    const cols = sizeGlideColumns({
      columns: [wide, wide, wide, wide, wide],
      rows: [[wide, wide, wide, wide, wide]],
      viewportWidth: 400,
    });
    expect(cols.every((c) => c.grow === 0)).toBe(true);
  });
});
