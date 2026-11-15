<script setup lang="ts">
import { computed } from "vue";
import { QUERYA_ICONS, type QueryaIconName } from "./registry";

const props = withDefaults(
  defineProps<{
    name: QueryaIconName;
    /** CSS px; default 14 for tree density. */
    size?: number;
    /** Decorative by default; set aria-label for meaningful icons. */
    label?: string;
  }>(),
  {
    size: 14,
  },
);

const ligature = computed(() => QUERYA_ICONS[props.name]);
</script>

<template>
  <span
    class="q-icon material-symbols-rounded"
    :style="{ fontSize: `${size}px`, width: `${size}px`, height: `${size}px` }"
    :aria-hidden="label ? undefined : true"
    :aria-label="label"
    role="img"
  >{{ ligature }}</span>
</template>

<style scoped>
.q-icon {
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  line-height: 1;
  font-variation-settings:
    "FILL" 0,
    "wght" 400,
    "GRAD" 0,
    "opsz" 24;
  user-select: none;
  color: currentColor;
  /* Optical match to Flutter Icon size */
  overflow: hidden;
}
</style>
