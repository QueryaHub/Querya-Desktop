<script setup lang="ts">
withDefaults(
  defineProps<{
    strong?: boolean;
    as?: string;
  }>(),
  { strong: false, as: "div" },
);
</script>

<template>
  <component
    :is="as"
    class="q-glass"
    :class="{ 'q-glass--strong': strong }"
  >
    <slot />
  </component>
</template>
