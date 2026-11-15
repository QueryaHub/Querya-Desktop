<script setup lang="ts">
withDefaults(
  defineProps<{
    vertical?: boolean;
  }>(),
  { vertical: false },
);
</script>

<template>
  <div
    class="q-divider"
    :class="{ vertical }"
    role="separator"
    :aria-orientation="vertical ? 'vertical' : 'horizontal'"
  />
</template>

<style scoped>
.q-divider {
  flex: 0 0 auto;
  background: color-mix(
    in srgb,
    var(--q-border) calc(var(--q-hairline-alpha) * 100%),
    transparent
  );
}

.q-divider:not(.vertical) {
  height: 1px;
  width: 100%;
}

.q-divider.vertical {
  width: 1px;
  height: 100%;
  align-self: stretch;
}
</style>
