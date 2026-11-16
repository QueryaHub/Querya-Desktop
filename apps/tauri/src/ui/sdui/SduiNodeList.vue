<script setup lang="ts">
import QueryaButton from "../QueryaButton.vue";
import type { SduiActionEvent, SduiNode } from "../../sdui";
import SduiNodeList from "./SduiNodeList.vue";

defineProps<{
  nodes: SduiNode[];
}>();

const emit = defineEmits<{
  action: [SduiActionEvent];
}>();

function onButton(nodeId: string, action: string | undefined) {
  emit("action", { nodeId, action: action ?? nodeId });
}
</script>

<template>
  <template v-for="(node, i) in nodes" :key="i">
    <p
      v-if="node.type === 'text'"
      class="sdui-text"
      :class="`sdui-text--${node.role ?? 'body'}`"
    >
      {{ node.text }}
    </p>
    <hr v-else-if="node.type === 'divider'" class="sdui-divider" />
    <div
      v-else-if="node.type === 'stack'"
      class="sdui-stack"
      :class="[
        `sdui-stack--${node.direction ?? 'column'}`,
        `sdui-stack--gap-${node.gap ?? 'md'}`,
      ]"
    >
      <SduiNodeList :nodes="node.children" @action="emit('action', $event)" />
    </div>
    <QueryaButton
      v-else-if="node.type === 'button'"
      :variant="node.variant ?? 'secondary'"
      size="md"
      :data-sdui-button="node.id"
      @click="onButton(node.id, node.action)"
    >
      {{ node.label }}
    </QueryaButton>
    <section
      v-else-if="node.type === 'panel'"
      class="sdui-panel sdui-panel--nested"
      :data-panel-id="node.id ?? undefined"
    >
      <header v-if="node.title" class="sdui-panel__header">
        <h3 class="sdui-panel__title">{{ node.title }}</h3>
      </header>
      <SduiNodeList :nodes="node.children" @action="emit('action', $event)" />
    </section>
  </template>
</template>

<style scoped>
.sdui-text {
  margin: 0;
  line-height: 1.45;
}

.sdui-text--heading {
  font-size: 18px;
  font-weight: 600;
  letter-spacing: -0.02em;
}

.sdui-text--body {
  font-size: 13px;
  color: var(--q-fg);
}

.sdui-text--muted {
  font-size: 12px;
  color: var(--q-fg-muted, var(--q-muted, #8b909a));
}

.sdui-divider {
  border: none;
  border-top: 1px solid var(--q-border);
  margin: 4px 0;
}

.sdui-stack {
  display: flex;
}

.sdui-stack--column {
  flex-direction: column;
}

.sdui-stack--row {
  flex-direction: row;
  flex-wrap: wrap;
  align-items: center;
}

.sdui-stack--gap-sm {
  gap: 6px;
}

.sdui-stack--gap-md {
  gap: 10px;
}

.sdui-stack--gap-lg {
  gap: 16px;
}

.sdui-panel--nested {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 12px 14px;
  border: 1px solid var(--q-border);
  border-radius: 8px;
  background: var(--q-surface);
}

.sdui-panel__title {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
}
</style>
