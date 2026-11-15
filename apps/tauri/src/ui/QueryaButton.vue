<script setup lang="ts">
import { computed, useSlots } from "vue";

/** Flutter `QueryaButtonVariant` — do not invent extra kinds. */
export type QueryaButtonVariant =
  | "primary"
  | "secondary"
  | "ghost"
  | "destructive";

/** Flutter `QueryaControlSize`. */
export type QueryaButtonSize = "sm" | "md" | "lg";

/** Flutter `QueryaButtonTone` for secondary/ghost. */
export type QueryaButtonTone = "normal" | "destructive";

const props = withDefaults(
  defineProps<{
    variant?: QueryaButtonVariant;
    size?: QueryaButtonSize;
    tone?: QueryaButtonTone;
    disabled?: boolean;
    loading?: boolean;
    /** Icon-only square (Flutter `QueryaButton.icon`). */
    icon?: boolean;
    active?: boolean;
    type?: "button" | "submit" | "reset";
    title?: string;
    ariaLabel?: string;
  }>(),
  {
    variant: "secondary",
    size: "md",
    tone: "normal",
    disabled: false,
    loading: false,
    icon: false,
    active: false,
    type: "button",
  },
);

const emit = defineEmits<{ click: [MouseEvent] }>();
const slots = useSlots();

const classes = computed(() => [
  "q-btn",
  `q-btn--${props.variant}`,
  `q-btn--${props.size}`,
  props.tone !== "normal" ? `q-btn--tone-${props.tone}` : null,
  props.icon ? "q-btn--icon" : null,
  props.active ? "q-btn--active" : null,
  props.loading ? "q-btn--loading" : null,
]);

const isDisabled = computed(() => props.disabled || props.loading);

function onClick(e: MouseEvent) {
  if (isDisabled.value) {
    e.preventDefault();
    return;
  }
  emit("click", e);
}
</script>

<template>
  <button
    :type="type"
    :class="classes"
    :disabled="isDisabled"
    :title="title"
    :aria-label="ariaLabel"
    :aria-busy="loading || undefined"
    @click="onClick"
  >
    <span v-if="loading" class="q-btn__spin" aria-hidden="true" />
    <span v-if="slots.default" class="q-btn__label" :class="{ hide: loading && icon }">
      <slot />
    </span>
  </button>
</template>

<style scoped>
.q-btn__spin {
  width: 0.85em;
  height: 0.85em;
  border: 2px solid color-mix(in srgb, currentColor 35%, transparent);
  border-top-color: currentColor;
  border-radius: 999px;
  animation: q-btn-spin 0.7s linear infinite;
  flex: 0 0 auto;
}

.q-btn__label.hide {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip: rect(0 0 0 0);
}

@keyframes q-btn-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
