<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { storeToRefs } from "pinia";
import type { Theme } from "@glideapps/glide-data-grid";
import { useQueryResultStore } from "../stores/queryResult";
import { useGridStagingStore } from "../stores/gridStaging";
import { ResultDataEditor } from "./glide/ResultDataEditor";
import {
  buildQueryaGlideTheme,
  subscribeThemeChanges,
} from "./glide/queryaGlideTheme";
import GridStagingToolbar from "./GridStagingToolbar.vue";
import "@glideapps/glide-data-grid/dist/index.css";

const emit = defineEmits<{
  applied: [];
}>();

const query = useQueryResultStore();
const staging = useGridStagingStore();
const { columns, rows, revision, rowCount, running } = storeToRefs(query);
const { revision: stagingRevision, isDirty, changeCount } =
  storeToRefs(staging);

const host = ref<HTMLDivElement | null>(null);
const size = ref({ width: 640, height: 320 });
let root: Root | null = null;
let ro: ResizeObserver | null = null;
let unsubTheme: (() => void) | null = null;
let glideTheme: Partial<Theme> = buildQueryaGlideTheme();

const showToolbar = computed(
  () => columns.value.length > 0 && !running.value,
);

const displayRows = computed(() => {
  if (staging.isDirty && staging.rowCount > 0) {
    return staging.effectiveRows();
  }
  return rows.value;
});

const editable = computed(
  () => !running.value && columns.value.length > 0 && rows.value.length > 0,
);

function onCellEdited(row: number, col: number, value: string) {
  staging.setCell(row, col, value);
}

function onCellClicked(row: number) {
  staging.selectedRowIndex = row;
}

function render() {
  if (!root || !host.value) return;
  root.render(
    createElement(ResultDataEditor, {
      columns: columns.value,
      rows: displayRows.value,
      width: Math.max(100, size.value.width),
      height: Math.max(100, size.value.height),
      theme: glideTheme,
      editable: editable.value,
      cellStatus: (r, c) => staging.cellStatus(r, c),
      rowStatus: (r) => staging.rowStatus(r),
      onCellEdited,
      onRowActivated: onCellClicked,
    }),
  );
}

function refreshTheme() {
  glideTheme = buildQueryaGlideTheme();
  render();
}

onMounted(() => {
  if (!host.value) return;
  root = createRoot(host.value);
  ro = new ResizeObserver((entries) => {
    const cr = entries[0]?.contentRect;
    if (!cr) return;
    size.value = {
      width: Math.floor(cr.width),
      height: Math.floor(cr.height),
    };
    render();
  });
  ro.observe(host.value);
  unsubTheme = subscribeThemeChanges(refreshTheme);
  refreshTheme();
});

watch(
  [columns, revision, rowCount, stagingRevision, isDirty, changeCount, running],
  () => render(),
);

onBeforeUnmount(() => {
  unsubTheme?.();
  unsubTheme = null;
  ro?.disconnect();
  ro = null;
  root?.unmount();
  root = null;
});
</script>

<template>
  <div class="result-grid-wrap" data-testid="result-grid-wrap">
    <GridStagingToolbar v-if="showToolbar" @applied="emit('applied')" />
    <div
      ref="host"
      class="result-grid"
      data-testid="result-grid"
      :data-staging-dirty="isDirty ? 'true' : 'false'"
      :aria-label="
        isDirty
          ? `Query results, ${changeCount} staged change(s)`
          : 'Query results'
      "
    />
  </div>
</template>

<style scoped>
.result-grid-wrap {
  width: 100%;
  height: 100%;
  min-height: 120px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.result-grid {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  background: var(--q-editor-bg);
  color: var(--q-foreground);
}
</style>
