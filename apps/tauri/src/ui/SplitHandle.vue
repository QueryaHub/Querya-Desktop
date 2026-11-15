<script setup lang="ts">
const emit = defineEmits<{
  pointerdown: [e: PointerEvent];
}>();
</script>

<template>
  <div
    class="split-handle"
    role="separator"
    aria-orientation="vertical"
    aria-label="Resize sidebar"
    data-testid="split-handle"
    @pointerdown="emit('pointerdown', $event)"
  />
</template>

<style scoped>
.split-handle {
  flex: 0 0 var(--q-split-handle);
  width: var(--q-split-handle);
  align-self: stretch;
  cursor: col-resize;
  position: relative;
  z-index: 3;
  background: transparent;
}

.split-handle::after {
  content: "";
  position: absolute;
  inset: 0 2px;
  background: color-mix(
    in srgb,
    var(--q-border) calc(var(--q-hairline-alpha) * 100%),
    transparent
  );
  transition: background var(--q-motion-fast) var(--q-motion-ease);
}

.split-handle:hover::after,
.split-handle:active::after {
  inset: 0 1px;
  background: color-mix(in srgb, var(--q-primary) 45%, transparent);
}
</style>
