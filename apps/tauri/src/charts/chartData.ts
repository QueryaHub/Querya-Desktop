/** Pure helpers — Flutter `ChartData` parity for Quick Charts (#1899). */

export type QuickChartType = "bar" | "line" | "pie";

export type ChartAggregation = "none" | "sum" | "count" | "avg" | "min" | "max";

export type ChartPoint = {
  label: string;
  value: number;
  time?: Date | null;
};

export type ChartSeries = {
  points: ChartPoint[];
  droppedRows: number;
};

export const MAX_LINE_POINTS = 50;
export const DEFAULT_TOP_N = 20;
export const PIE_TOP_N = 8;
export const OTHER_LABEL = "Other";
export const TOP_N_CHOICES: (number | null)[] = [8, 10, 20, 50, null];

export function parseNumber(raw: string): number | null {
  const text = raw.trim();
  if (!text) return null;
  const value = Number(text);
  if (!Number.isFinite(value)) return null;
  return value;
}

/** ISO-ish date / timestamp; null when it does not fit. */
export function parseTime(raw: string): Date | null {
  const s = raw.trim();
  if (s.length < 10) return null;
  if (!/^\d{4}-\d{2}-\d{2}/.test(s)) return null;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function numericColumns(
  columns: string[],
  rows: string[][],
): number[] {
  const result: number[] = [];
  for (let c = 0; c < columns.length; c++) {
    let seen = 0;
    let ok = true;
    for (const row of rows) {
      if (c >= row.length) continue;
      const cell = (row[c] ?? "").trim();
      if (!cell || cell === "NULL") continue;
      if (parseNumber(cell) == null) {
        ok = false;
        break;
      }
      seen++;
    }
    if (ok && seen > 0) result.push(c);
  }
  return result;
}

export function isTimeColumn(rows: string[][], labelColumn: number): boolean {
  let seen = 0;
  for (const row of rows) {
    if (labelColumn >= row.length) continue;
    const cell = (row[labelColumn] ?? "").trim();
    if (!cell || cell === "NULL") continue;
    if (!parseTime(cell)) return false;
    seen++;
  }
  return seen > 0;
}

export function defaultAggregation(opts: {
  rows: string[][];
  labelColumn: number | null;
  valueColumn: number;
}): ChartAggregation {
  const { rows, labelColumn, valueColumn } = opts;
  if (labelColumn == null) return "none";
  const seen = new Set<string>();
  for (const row of rows) {
    if (labelColumn >= row.length || valueColumn >= row.length) continue;
    if (parseNumber(row[valueColumn] ?? "") == null) continue;
    const label = row[labelColumn] ?? "";
    if (seen.has(label)) return "sum";
    seen.add(label);
  }
  return "none";
}

function parsePoints(
  rows: string[][],
  labelColumn: number | null,
  valueColumn: number,
): ChartPoint[] {
  const points: ChartPoint[] = [];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i] ?? [];
    if (valueColumn >= row.length) continue;
    const v = parseNumber(row[valueColumn] ?? "");
    if (v == null) continue;
    const label =
      labelColumn != null && labelColumn < row.length
        ? (row[labelColumn] ?? "")
        : String(i + 1);
    points.push({ label, value: v, time: parseTime(label) });
  }
  return points;
}

function aggregate(
  points: ChartPoint[],
  aggregation: ChartAggregation,
): ChartPoint[] {
  const groups = new Map<
    string,
    { sum: number; count: number; min: number; max: number; time?: Date | null }
  >();
  for (const p of points) {
    let g = groups.get(p.label);
    if (!g) {
      g = {
        sum: 0,
        count: 0,
        min: Number.POSITIVE_INFINITY,
        max: Number.NEGATIVE_INFINITY,
        time: p.time,
      };
      groups.set(p.label, g);
    }
    g.sum += p.value;
    g.count += 1;
    g.min = Math.min(g.min, p.value);
    g.max = Math.max(g.max, p.value);
  }
  const out: ChartPoint[] = [];
  for (const [label, g] of groups) {
    let value = g.sum;
    switch (aggregation) {
      case "count":
        value = g.count;
        break;
      case "avg":
        value = g.count ? g.sum / g.count : 0;
        break;
      case "min":
        value = g.min;
        break;
      case "max":
        value = g.max;
        break;
      case "sum":
      case "none":
        value = g.sum;
        break;
    }
    out.push({ label, value, time: g.time });
  }
  return out;
}

export function buildChartSeries(opts: {
  rows: string[][];
  labelColumn: number | null;
  valueColumn: number;
  type: QuickChartType;
  aggregation?: ChartAggregation;
  topN?: number | null;
}): ChartSeries {
  const {
    rows,
    labelColumn,
    valueColumn,
    type,
    aggregation = "none",
    topN,
  } = opts;
  let points = parsePoints(rows, labelColumn, valueColumn);
  if (aggregation !== "none") {
    points = aggregate(points, aggregation);
  }

  if (type === "line") {
    if (
      labelColumn != null &&
      isTimeColumn(rows, labelColumn) &&
      points.every((p) => p.time)
    ) {
      points = [...points].sort(
        (a, b) => (a.time?.getTime() ?? 0) - (b.time?.getTime() ?? 0),
      );
    }
    if (points.length <= MAX_LINE_POINTS) {
      return { points, droppedRows: 0 };
    }
    return {
      points: points.slice(0, MAX_LINE_POINTS),
      droppedRows: points.length - MAX_LINE_POINTS,
    };
  }

  if (type === "pie") {
    points = points.filter((p) => p.value > 0);
    points.sort((a, b) => b.value - a.value);
  }

  if (topN == null || points.length <= topN) {
    return { points, droppedRows: 0 };
  }

  const ranked = [...points].sort((a, b) => b.value - a.value);
  const head = ranked.slice(0, topN);
  const rest = ranked.slice(topN).reduce((s, p) => s + p.value, 0);
  return {
    points: [...head, { label: OTHER_LABEL, value: rest }],
    droppedRows: 0,
  };
}

export function defaultLabelColumn(
  columns: string[],
  valueCol: number,
  numeric: number[],
): number | null {
  for (let i = 0; i < columns.length; i++) {
    if (i !== valueCol && !numeric.includes(i)) return i;
  }
  for (let i = 0; i < columns.length; i++) {
    if (i !== valueCol) return i;
  }
  return null;
}

export function rowsToChartStrings(rows: unknown[][]): string[][] {
  return rows.map((row) =>
    row.map((cell) => {
      if (cell === null || cell === undefined) return "";
      if (typeof cell === "string") return cell === "NULL" ? "" : cell;
      if (typeof cell === "number" || typeof cell === "boolean") {
        return String(cell);
      }
      return JSON.stringify(cell);
    }),
  );
}
