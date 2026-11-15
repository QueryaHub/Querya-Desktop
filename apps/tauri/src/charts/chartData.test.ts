import { describe, expect, it } from "vitest";
import {
  buildChartSeries,
  defaultAggregation,
  numericColumns,
  parseNumber,
} from "./chartData";

describe("chartData", () => {
  const columns = ["city", "sales", "qty"];
  const rows = [
    ["Paris", "10", "2"],
    ["Paris", "5", "1"],
    ["Berlin", "7", "3"],
  ];

  it("detects numeric columns", () => {
    expect(numericColumns(columns, rows)).toEqual([1, 2]);
    expect(parseNumber(" 3.5 ")).toBe(3.5);
    expect(parseNumber("x")).toBeNull();
  });

  it("defaults aggregation to sum when labels repeat", () => {
    expect(
      defaultAggregation({ rows, labelColumn: 0, valueColumn: 1 }),
    ).toBe("sum");
    expect(
      defaultAggregation({ rows, labelColumn: null, valueColumn: 1 }),
    ).toBe("none");
  });

  it("builds bar series with topN Other bucket", () => {
    const series = buildChartSeries({
      rows,
      labelColumn: 0,
      valueColumn: 1,
      type: "bar",
      aggregation: "sum",
      topN: 1,
    });
    expect(series.points).toHaveLength(2);
    expect(series.points[0]?.label).toBe("Paris");
    expect(series.points[0]?.value).toBe(15);
    expect(series.points[1]?.label).toBe("Other");
    expect(series.points[1]?.value).toBe(7);
  });

  it("caps line series", () => {
    const many = Array.from({ length: 60 }, (_, i) => [
      String(i),
      String(i),
    ]);
    const series = buildChartSeries({
      rows: many,
      labelColumn: 0,
      valueColumn: 1,
      type: "line",
    });
    expect(series.points).toHaveLength(50);
    expect(series.droppedRows).toBe(10);
  });
});
