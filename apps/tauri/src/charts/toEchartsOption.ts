import type { EChartsOption } from "echarts";
import type { ChartSeries, QuickChartType } from "./chartData";

export function toEchartsOption(opts: {
  type: QuickChartType;
  series: ChartSeries;
  title: string;
  dark: boolean;
}): EChartsOption {
  const { type, series, title, dark } = opts;
  const text = dark ? "#e2e8f0" : "#1e293b";
  const muted = dark ? "#94a3b8" : "#64748b";
  const axis = dark ? "#334155" : "#cbd5e1";
  const labels = series.points.map((p) => p.label);
  const values = series.points.map((p) => p.value);

  const base: EChartsOption = {
    backgroundColor: "transparent",
    textStyle: { color: text },
    title: {
      text: title,
      left: "center",
      top: 8,
      textStyle: { color: text, fontSize: 13, fontWeight: 600 },
    },
    tooltip: { trigger: type === "pie" ? "item" : "axis" },
    grid: {
      left: 48,
      right: 24,
      top: 48,
      bottom: type === "pie" ? 24 : 40,
    },
  };

  if (type === "pie") {
    return {
      ...base,
      legend: {
        type: "scroll",
        orient: "vertical",
        right: 8,
        top: 48,
        textStyle: { color: muted },
      },
      series: [
        {
          type: "pie",
          radius: ["35%", "65%"],
          center: ["40%", "55%"],
          data: series.points.map((p) => ({ name: p.label, value: p.value })),
          label: { color: muted },
        },
      ],
    };
  }

  return {
    ...base,
    xAxis: {
      type: "category",
      data: labels,
      axisLabel: { color: muted, hideOverlap: true },
      axisLine: { lineStyle: { color: axis } },
    },
    yAxis: {
      type: "value",
      axisLabel: { color: muted },
      splitLine: { lineStyle: { color: axis, opacity: 0.45 } },
    },
    series: [
      {
        type,
        data: values,
        smooth: type === "line",
        itemStyle: { color: "#22d3ee" },
        areaStyle: type === "line" ? { opacity: 0.08 } : undefined,
      },
    ],
  };
}
