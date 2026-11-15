<script setup lang="ts">
import { computed } from "vue";
import { useWorkspaceStore } from "../stores/workspace";
import { useQueryaMotion } from "../motion";

const workspace = useWorkspaceStore();
const motion = useQueryaMotion();

const stripStyle = computed(() => ({
  transitionDuration: `${motion.duration("fast")}ms`,
  transitionTimingFunction: motion.easing("standard"),
}));

function onClose(e: MouseEvent, id: string) {
  e.stopPropagation();
  workspace.closeTab(id);
}
</script>

<template>
  <div class="tabstrip" data-testid="tab-strip" :style="stripStyle">
    <div class="tabs" role="tablist" aria-label="Workspace tabs">
      <button
        v-for="tab in workspace.tabs"
        :key="tab.id"
        type="button"
        class="tab"
        role="tab"
        :aria-selected="tab.id === workspace.activeId"
        :class="{ active: tab.id === workspace.activeId }"
        :data-testid="`tab-${tab.id}`"
        @click="workspace.activate(tab.id)"
      >
        <span class="title">{{ tab.title }}</span>
        <span
          class="close"
          role="button"
          tabindex="0"
          aria-label="Close tab"
          @click="onClose($event, tab.id)"
          @keydown.enter.prevent="workspace.closeTab(tab.id)"
        >
          ×
        </span>
      </button>
    </div>
    <button
      type="button"
      class="add"
      data-testid="tab-add"
      aria-label="New tab"
      @click="workspace.addTab()"
    >
      +
    </button>
  </div>
</template>

<style scoped>
.tabstrip {
  display: flex;
  align-items: stretch;
  gap: var(--q-space-1);
  min-height: 36px;
  padding: var(--q-space-1) var(--q-space-2) 0;
  border-bottom: 1px solid var(--q-border);
  background: color-mix(in srgb, var(--q-card) 70%, transparent);
  transition-property: background-color, border-color;
}

.tabs {
  display: flex;
  align-items: stretch;
  gap: 2px;
  min-width: 0;
  overflow-x: auto;
  flex: 1;
}

.tab {
  appearance: none;
  border: 1px solid transparent;
  border-bottom: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  font: inherit;
  font-size: var(--q-text-sm);
  padding: 0.35rem 0.55rem 0.45rem 0.75rem;
  border-radius: var(--q-radius-md) var(--q-radius-md) 0 0;
  display: inline-flex;
  align-items: center;
  gap: var(--q-space-2);
  cursor: pointer;
  max-width: 12rem;
  transition:
    background-color var(--q-motion-fast) var(--q-motion-ease),
    color var(--q-motion-fast) var(--q-motion-ease);
}

.tab:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.tab.active {
  background: var(--q-background);
  color: var(--q-foreground);
  border-color: var(--q-border);
  box-shadow: inset 0 -1px 0 var(--q-background);
}

.title {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.close {
  display: grid;
  place-items: center;
  width: 1.1rem;
  height: 1.1rem;
  border-radius: var(--q-radius-sm);
  opacity: 0.55;
  font-size: 0.95rem;
  line-height: 1;
}

.close:hover {
  opacity: 1;
  background: var(--q-accent);
}

.add {
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  width: 2rem;
  border-radius: var(--q-radius-sm);
  cursor: pointer;
  font-size: 1.1rem;
  margin-bottom: 2px;
}

.add:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}
</style>
