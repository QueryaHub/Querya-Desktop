<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from "vue";
import { createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { storeToRefs } from "pinia";
import type { Theme } from "@glideapps/glide-data-grid";
import { useQueryResultStore } from "../stores/queryResult";
import { ResultDataEditor } from "./glide/ResultDataEditor";
import {
  buildQueryaGlideTheme,
  subscribeThemeChanges,
} from "./glide/queryaGlideTheme";
import "@glideapps/glide-data-grid/dist/index.css";

const query = useQueryResultStore();
const { columns, rows } = storeToRefs(query);

const host = ref<HTMLDivElement | null>(null);
const size = ref({ width: 640, height: 320 });
let root: Root | null = null;
let ro: ResizeObserver | null = null;
let unsubTheme: (() => void) | null = null;
let glideTheme: Partial<Theme> = buildQueryaGlideTheme();

function render() {
  if (!root || !host.value) return;
  root.render(
    createElement(ResultDataEditor, {
      columns: columns.value,
      rows: rows.value,
      width: Math.max(100, size.value.width),
      height: Math.max(100, size.value.height),
      theme: glideTheme,
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

watch([columns, rows], () => render(), { deep: true });

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
  <div
    ref="host"
    class="result-grid"
    data-testid="result-grid"
    aria-label="Query results"
  />
</template>

<style scoped>
.result-grid {
  width: 100%;
  height: 100%;
  min-height: 120px;
  overflow: hidden;
  background: var(--q-editor-bg);
  color: var(--q-foreground);
}
</style>
