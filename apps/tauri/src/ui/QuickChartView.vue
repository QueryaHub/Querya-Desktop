<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import * as echarts from "echarts/core";
import { BarChart, LineChart, PieChart } from "echarts/charts";
import {
  GridComponent,
  LegendComponent,
  TitleComponent,
  TooltipComponent,
} from "echarts/components";
import { CanvasRenderer } from "echarts/renderers";
import {
  buildChartSeries,
  DEFAULT_TOP_N,
  defaultAggregation,
  defaultLabelColumn,
  numericColumns,
  PIE_TOP_N,
  TOP_N_CHOICES,
  type ChartAggregation,
  type QuickChartType,
  rowsToChartStrings,
} from "../charts/chartData";
import { toEchartsOption } from "../charts/toEchartsOption";

echarts.use([
  BarChart,
  LineChart,
  PieChart,
  GridComponent,
  LegendComponent,
  TitleComponent,
  TooltipComponent,
  CanvasRenderer,
]);

const props = defineProps<{
  columns: string[];
  rows: unknown[][];
}>();

const host = ref<HTMLDivElement | null>(null);
let chart: echarts.ECharts | null = null;
let ro: ResizeObserver | null = null;

const chartType = ref<QuickChartType>("bar");
const labelCol = ref<number | null>(null);
const valueCol = ref<number | null>(null);
const aggregation = ref<ChartAggregation>("none");
const topN = ref<number | null>(DEFAULT_TOP_N);

const stringRows = computed(() => rowsToChartStrings(props.rows));
const numeric = computed(() =>
  numericColumns(props.columns, stringRows.value),
);

const dark = computed(() =>
  document.documentElement.dataset.theme === "dark" ||
  document.documentElement.classList.contains("dark") ||
  window.matchMedia("(prefers-color-scheme: dark)").matches,
);

function recomputeDefaults() {
  const nums = numeric.value;
  if (nums.length === 0) {
    valueCol.value = null;
    labelCol.value = null;
    return;
  }
  if (valueCol.value == null || !nums.includes(valueCol.value)) {
    valueCol.value = nums[nums.length - 1]!;
  }
  if (labelCol.value != null && labelCol.value >= props.columns.length) {
    labelCol.value = null;
  }
  if (labelCol.value == null) {
    labelCol.value = defaultLabelColumn(
      props.columns,
      valueCol.value!,
      nums,
    );
  }
  aggregation.value = defaultAggregation({
    rows: stringRows.value,
    labelColumn: labelCol.value,
    valueColumn: valueCol.value!,
  });
  topN.value = chartType.value === "pie" ? PIE_TOP_N : DEFAULT_TOP_N;
}

const series = computed(() => {
  if (valueCol.value == null) {
    return { points: [], droppedRows: 0 };
  }
  const agg = chartType.value === "line" ? "none" : aggregation.value;
  return buildChartSeries({
    rows: stringRows.value,
    labelColumn: labelCol.value,
    valueColumn: valueCol.value,
    type: chartType.value,
    aggregation: agg,
    topN: chartType.value === "line" ? null : topN.value,
  });
});

const title = computed(() => {
  if (valueCol.value == null) return "";
  const y = props.columns[valueCol.value] ?? "Y";
  const x =
    labelCol.value == null
      ? "(row #)"
      : (props.columns[labelCol.value] ?? "X");
  const base = `${y} by ${x}`;
  const agg =
    chartType.value === "line" ? "none" : aggregation.value;
  return agg === "none" ? base : `${base} (${agg})`;
});

function renderChart() {
  if (!host.value || valueCol.value == null) {
    chart?.clear();
    return;
  }
  if (!chart) chart = echarts.init(host.value, undefined, { renderer: "canvas" });
  chart.setOption(
    toEchartsOption({
      type: chartType.value,
      series: series.value,
      title: title.value,
      dark: dark.value,
    }),
    true,
  );
}

watch(
  () => [props.columns, props.rows] as const,
  () => {
    recomputeDefaults();
    renderChart();
  },
  { deep: true },
);

watch([chartType, labelCol, valueCol, aggregation, topN, series], () =>
  renderChart(),
);

onMounted(() => {
  recomputeDefaults();
  if (host.value) {
    chart = echarts.init(host.value);
    ro = new ResizeObserver(() => chart?.resize());
    ro.observe(host.value);
  }
  renderChart();
});

onBeforeUnmount(() => {
  ro?.disconnect();
  ro = null;
  chart?.dispose();
  chart = null;
});
</script>

<template>
  <div class="quick-chart" data-testid="quick-chart">
    <div class="controls">
      <div class="types" role="tablist">
        <button
          v-for="t in (['bar', 'line', 'pie'] as const)"
          :key="t"
          type="button"
          class="tab"
          :class="{ active: chartType === t }"
          :data-testid="`chart-type-${t}`"
          @click="chartType = t"
        >
          {{ t[0]!.toUpperCase() + t.slice(1) }}
        </button>
      </div>

      <label>
        {{ chartType === "line" ? "Time" : "Category" }}
        <select
          data-testid="chart-label-col"
          :value="labelCol === null ? '' : String(labelCol)"
          @change="
            labelCol =
              ($event.target as HTMLSelectElement).value === ''
                ? null
                : Number(($event.target as HTMLSelectElement).value)
          "
        >
          <option value="">(row #)</option>
          <option
            v-for="(name, i) in columns"
            :key="i"
            :value="i"
          >
            {{ name }}
          </option>
        </select>
      </label>

      <label>
        Value
        <select
          data-testid="chart-value-col"
          :value="valueCol ?? ''"
          :disabled="!numeric.length"
          @change="valueCol = Number(($event.target as HTMLSelectElement).value)"
        >
          <option
            v-for="i in numeric"
            :key="i"
            :value="i"
          >
            {{ columns[i] }}
          </option>
        </select>
      </label>

      <label v-if="chartType !== 'line'">
        Aggregation
        <select
          data-testid="chart-aggregation"
          :value="aggregation"
          @change="
            aggregation = ($event.target as HTMLSelectElement)
              .value as ChartAggregation
          "
        >
          <option value="none">None</option>
          <option value="sum">Sum</option>
          <option value="count">Count</option>
          <option value="avg">Avg</option>
          <option value="min">Min</option>
          <option value="max">Max</option>
        </select>
      </label>

      <label v-if="chartType !== 'line'">
        Top N
        <select
          data-testid="chart-topn"
          :value="topN === null ? 'all' : String(topN)"
          @change="
            topN =
              ($event.target as HTMLSelectElement).value === 'all'
                ? null
                : Number(($event.target as HTMLSelectElement).value)
          "
        >
          <option
            v-for="n in TOP_N_CHOICES"
            :key="String(n)"
            :value="n === null ? 'all' : n"
          >
            {{ n === null ? "All" : n }}
          </option>
        </select>
      </label>
    </div>

    <p v-if="!numeric.length" class="empty" data-testid="chart-empty">
      No numeric columns to chart.
    </p>
    <div v-else ref="host" class="canvas" data-testid="chart-canvas" />
    <p v-if="series.droppedRows" class="hint">
      Showing first {{ series.points.length }} points ·
      {{ series.droppedRows }} omitted
    </p>
  </div>
</template>

<style scoped>
.quick-chart {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 8px 10px;
  background: var(--q-editor-bg);
  color: var(--q-foreground);
}

.controls {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
  flex-shrink: 0;
}

.types {
  display: inline-flex;
  gap: 2px;
  padding: 2px;
  border-radius: 6px;
  background: color-mix(in srgb, var(--q-foreground) 6%, transparent);
}

.tab {
  font: inherit;
  font-size: 12px;
  border: none;
  border-radius: 4px;
  padding: 4px 10px;
  cursor: pointer;
  background: transparent;
  color: var(--q-foreground);
}

.tab.active {
  background: color-mix(in srgb, var(--q-accent, #22d3ee) 28%, transparent);
  font-weight: 600;
}

label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: color-mix(in srgb, var(--q-foreground) 75%, transparent);
}

select {
  font: inherit;
  font-size: 12px;
  max-width: 160px;
  padding: 3px 6px;
  border-radius: 4px;
  border: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  background: var(--q-sidebar-bg);
  color: var(--q-foreground);
}

.canvas {
  flex: 1;
  min-height: 180px;
}

.empty,
.hint {
  margin: 0;
  font-size: 12px;
  color: color-mix(in srgb, var(--q-foreground) 65%, transparent);
}

.empty {
  padding: 24px 8px;
  text-align: center;
}
</style>
