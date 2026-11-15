<script setup lang="ts">
import { computed, markRaw, nextTick, ref, watch } from "vue";
import { VueFlow, useVueFlow } from "@vue-flow/core";
import { Background } from "@vue-flow/background";
import { Controls } from "@vue-flow/controls";
import type { Edge, Node } from "@vue-flow/core";
import "@vue-flow/core/dist/style.css";
import "@vue-flow/core/dist/theme-default.css";
import "@vue-flow/controls/dist/style.css";
import type { ErdSchema } from "../../api/connection";
import ErdTableNode from "./ErdTableNode.vue";
import { schemaToFlow, type ErdTableNodeData } from "./layout";

const props = defineProps<{
  schema: ErdSchema | null;
  loading?: boolean;
  error?: string | null;
}>();

const FLOW_ID = "erd-canvas";
const nodes = ref<Node<ErdTableNodeData>[]>([]);
const edges = ref<Edge[]>([]);
const nodeTypes = { erdTable: markRaw(ErdTableNode) };

const { fitView, onNodesInitialized } = useVueFlow({ id: FLOW_ID });

onNodesInitialized(() => {
  void fitView({ padding: 0.15, duration: 200 });
});

const empty = computed(
  () => !props.loading && !props.error && (props.schema?.tables.length ?? 0) === 0,
);

watch(
  () => props.schema,
  async (schema) => {
    if (!schema) {
      nodes.value = [];
      edges.value = [];
      return;
    }
    const mapped = schemaToFlow(schema);
    nodes.value = mapped.nodes;
    edges.value = mapped.edges;
    await nextTick();
    void fitView({ padding: 0.15, duration: 200 });
  },
  { immediate: true },
);
</script>

<template>
  <div class="erd-canvas" data-testid="erd-canvas">
    <div v-if="loading" class="banner">Loading schema…</div>
    <div v-else-if="error" class="banner err">{{ error }}</div>
    <div v-else-if="empty" class="banner">No tables to diagram.</div>
    <VueFlow
      :id="FLOW_ID"
      v-model:nodes="nodes"
      v-model:edges="edges"
      :node-types="nodeTypes"
      :nodes-draggable="true"
      :nodes-connectable="false"
      :elements-selectable="true"
      :min-zoom="0.2"
      :max-zoom="2"
      fit-view-on-init
      class="flow"
    >
      <Background pattern-color="var(--q-border)" :gap="18" />
      <Controls position="bottom-left" />
    </VueFlow>
  </div>
</template>

<style scoped>
.erd-canvas {
  position: relative;
  height: 100%;
  min-height: 0;
  background: var(--q-canvas);
}

.flow {
  width: 100%;
  height: 100%;
}

.banner {
  position: absolute;
  z-index: 5;
  top: 12px;
  left: 50%;
  transform: translateX(-50%);
  padding: 6px 12px;
  border-radius: var(--q-radius-sm);
  background: var(--q-surface);
  border: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  color: var(--q-muted-foreground);
  font-size: var(--q-text-sm);
  pointer-events: none;
}

.banner.err {
  color: var(--q-destructive);
}

:deep(.vue-flow__controls) {
  box-shadow: var(--q-shadow-sm);
  border-radius: var(--q-radius-sm);
  overflow: hidden;
  border: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
}

:deep(.vue-flow__controls-button) {
  background: var(--q-surface);
  border: 0;
  border-bottom: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  fill: var(--q-foreground);
}

:deep(.vue-flow__edge-path) {
  stroke: var(--q-primary);
}

:deep(.vue-flow__edge-textbg) {
  fill: var(--q-canvas);
}
</style>
