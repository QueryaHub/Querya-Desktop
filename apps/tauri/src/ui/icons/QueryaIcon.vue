<script setup lang="ts">
import { computed } from "vue";
import { QUERYA_ICONS, type QueryaIconName } from "./registry";

const props = withDefaults(
  defineProps<{
    name: QueryaIconName;
    /** CSS px; default 14 for tree density. */
    size?: number;
    strokeWidth?: number;
    /** Decorative by default; set aria-label for meaningful icons. */
    label?: string;
  }>(),
  {
    size: 14,
    strokeWidth: 2,
  },
);

const cmp = computed(() => QUERYA_ICONS[props.name]);
</script>

<template>
  <component
    :is="cmp"
    class="q-icon"
    :size="props.size"
    :stroke-width="props.strokeWidth"
    :aria-hidden="label ? undefined : true"
    :aria-label="label"
    role="img"
  />
</template>

<style scoped>
.q-icon {
  flex-shrink: 0;
  display: inline-block;
  vertical-align: middle;
  color: currentColor;
}
</style>
