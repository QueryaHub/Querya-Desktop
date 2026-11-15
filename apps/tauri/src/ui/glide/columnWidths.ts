/** Flutter `ResultGridMetrics` — content-fit then spare fill. */
export const MIN_COLUMN_WIDTH = 56;
export const MAX_COLUMN_WIDTH = 280;
export const COLUMN_WIDTH_SAMPLE_ROWS = 40;
/** Glide row-marker gutter approximation when sizing against viewport. */
export const ROW_MARKER_WIDTH = 52;

function cellChars(value: unknown): number {
  if (value === null || value === undefined) return 4; // NULL
  if (typeof value === "string") return value.length;
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value).length;
  }
  return JSON.stringify(value).length;
}

/**
 * Content-based widths (Flutter `computeResultGridColumnWidths`), then
 * remaining viewport space is claimed via Glide `grow` so columns fill the
 * grid when there is spare room.
 */
export function sizeGlideColumns(opts: {
  columns: string[];
  rows: unknown[][];
  viewportWidth: number;
}): { id: string; title: string; width: number; grow: number }[] {
  const { columns, rows, viewportWidth } = opts;
  if (columns.length === 0) return [];

  const sample = Math.min(rows.length, COLUMN_WIDTH_SAMPLE_ROWS);
  const widths = columns.map((title, c) => {
    let maxChars = title.length;
    for (let r = 0; r < sample; r++) {
      const n = cellChars(rows[r]?.[c]);
      if (n > maxChars) maxChars = n;
    }
    const content = maxChars * 7.5 + 38;
    return Math.min(MAX_COLUMN_WIDTH, Math.max(MIN_COLUMN_WIDTH, content));
  });

  const available = Math.max(0, viewportWidth - ROW_MARKER_WIDTH);
  const total = widths.reduce((a, b) => a + b, 0);
  const hasSpare = available - total > 0.5;

  return columns.map((title, i) => ({
    id: title,
    title,
    width: Math.round(widths[i]!),
    // Equal grow fills leftover width (Flutter spare distribute → fill screen).
    grow: hasSpare ? 1 : 0,
  }));
}
