<script setup lang="ts">
import { ref } from "vue";
import { storeToRefs } from "pinia";
import { useQueryResultStore } from "../stores/queryResult";
import ResultGrid from "./ResultGrid.vue";
import QuickChartView from "./QuickChartView.vue";

const emit = defineEmits<{
  applied: [];
}>();

type ResultViewMode = "grid" | "charts";

const query = useQueryResultStore();
const { columns, rows } = storeToRefs(query);
const mode = ref<ResultViewMode>("grid");
</script>

<template>
  <div class="result-view" data-testid="result-view-pane">
    <div class="strip" role="tablist">
      <button
        type="button"
        class="tab"
        :class="{ active: mode === 'grid' }"
        data-testid="result-mode-grid"
        @click="mode = 'grid'"
      >
        Grid
      </button>
      <button
        type="button"
        class="tab"
        :class="{ active: mode === 'charts' }"
        data-testid="result-mode-charts"
        @click="mode = 'charts'"
      >
        Charts
      </button>
    </div>
    <div class="body">
      <ResultGrid v-if="mode === 'grid'" @applied="emit('applied')" />
      <QuickChartView
        v-else
        :columns="columns"
        :rows="rows"
      />
    </div>
  </div>
</template>

<style scoped>
.result-view {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.strip {
  display: flex;
  gap: 2px;
  flex-shrink: 0;
  padding: 0 0 6px;
}

.tab {
  font: inherit;
  font-size: 11px;
  font-weight: 600;
  border: none;
  border-radius: 4px;
  padding: 3px 10px;
  cursor: pointer;
  background: transparent;
  color: var(--q-muted-foreground);
}

.tab.active {
  background: color-mix(in srgb, var(--q-foreground) 8%, transparent);
  color: var(--q-foreground);
}

.body {
  flex: 1;
  min-height: 0;
}
</style>
