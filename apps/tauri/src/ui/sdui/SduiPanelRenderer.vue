<script setup lang="ts">
import type { SduiActionEvent, SduiPanelNode } from "../../sdui";
import SduiNodeList from "./SduiNodeList.vue";

const props = defineProps<{
  descriptor: SduiPanelNode;
}>();

const emit = defineEmits<{
  action: [SduiActionEvent];
}>();
</script>

<template>
  <section
    class="sdui-panel"
    data-testid="sdui-panel"
    :data-panel-id="props.descriptor.id ?? undefined"
  >
    <header v-if="props.descriptor.title" class="sdui-panel__header">
      <h2 class="sdui-panel__title">{{ props.descriptor.title }}</h2>
    </header>
    <div class="sdui-panel__body">
      <SduiNodeList
        :nodes="props.descriptor.children"
        @action="emit('action', $event)"
      />
    </div>
  </section>
</template>

<style scoped>
.sdui-panel {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 18px;
  border: 1px solid var(--q-border);
  border-radius: 10px;
  background: var(--q-surface);
  color: var(--q-fg);
  max-width: 480px;
  width: 100%;
}

.sdui-panel__title {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
  letter-spacing: -0.01em;
}

.sdui-panel__body {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
</style>
