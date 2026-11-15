<script setup lang="ts">
/**
 * Flutter InterfaceScaleSlider: snap to presets; hold Shift for 1% steps.
 * Label updates while dragging; scale commits on release (avoids zoom fighting the thumb).
 */
import { computed, onMounted, onUnmounted, ref } from "vue";

const SCALE_PRESETS = [75, 85, 90, 100, 110, 125, 150, 175, 200] as const;
const MIN = 75;
const MAX = 200;
const LAST_PRESET = SCALE_PRESETS.length - 1;

const props = defineProps<{ modelValue: number }>();
const emit = defineEmits<{ "update:modelValue": [value: number] }>();

const fineControl = ref(false);
const dragging = ref(false);
const dragFine = ref(false);
const dragScale = ref<number | null>(null);

/** Shift locked for the drag so releasing mid-drag does not retarget the thumb. */
const activeFine = computed(() =>
  dragging.value ? dragFine.value : fineControl.value,
);

const displayScale = computed(() => dragScale.value ?? clampScale(props.modelValue));

const pctLabel = computed(() => `${Math.round(displayScale.value)}%`);

/** 0–100 for soft filled track (visual only). */
const fillPct = computed(
  () => ((displayScale.value - MIN) / (MAX - MIN)) * 100,
);

const sliderMin = computed(() => (activeFine.value ? MIN : 0));
const sliderMax = computed(() => (activeFine.value ? MAX : LAST_PRESET));
const sliderPosition = computed(() => {
  const scale = displayScale.value;
  return activeFine.value ? scale : nearestPresetIndex(scale);
});

function clampScale(scale: number): number {
  if (!Number.isFinite(scale)) return 100;
  return Math.min(MAX, Math.max(MIN, scale));
}

function nearestPresetIndex(scale: number): number {
  let best = 0;
  let bestDist = Infinity;
  for (let i = 0; i < SCALE_PRESETS.length; i++) {
    const dist = Math.abs(SCALE_PRESETS[i]! - scale);
    if (dist < bestDist) {
      bestDist = dist;
      best = i;
    }
  }
  return best;
}

function scaleFromPosition(position: number, fine: boolean): number {
  if (fine) return Math.round(clampScale(position));
  const i = Math.min(LAST_PRESET, Math.max(0, Math.round(position)));
  return SCALE_PRESETS[i]!;
}

function beginDrag() {
  dragging.value = true;
  dragFine.value = fineControl.value;
}

function onInput(e: Event) {
  if (!dragging.value) beginDrag();
  const raw = Number((e.target as HTMLInputElement).value);
  dragScale.value = scaleFromPosition(raw, dragFine.value);
}

function onChange(e: Event) {
  if (!dragging.value) beginDrag();
  const raw = Number((e.target as HTMLInputElement).value);
  const next = scaleFromPosition(raw, dragFine.value);
  dragging.value = false;
  dragFine.value = false;
  dragScale.value = null;
  emit("update:modelValue", next);
}

function onKey(e: KeyboardEvent) {
  if (dragging.value) return;
  fineControl.value = e.shiftKey;
}

onMounted(() => {
  window.addEventListener("keydown", onKey, true);
  window.addEventListener("keyup", onKey, true);
});
onUnmounted(() => {
  window.removeEventListener("keydown", onKey, true);
  window.removeEventListener("keyup", onKey, true);
});
</script>

<template>
  <div class="scale-row">
    <input
      class="scale-slider"
      type="range"
      :min="sliderMin"
      :max="sliderMax"
      step="1"
      :value="sliderPosition"
      :style="{ '--scale-fill': `${fillPct}%` }"
      :aria-valuetext="pctLabel"
      aria-label="Interface scale"
      @pointerdown="beginDrag"
      @input="onInput"
      @change="onChange"
    />
    <span class="scale-pct">{{ pctLabel }}</span>
  </div>
</template>

<style scoped>
.scale-row {
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 32px;
}

.scale-slider {
  flex: 1;
  min-width: 0;
  height: 28px;
  margin: 0;
  appearance: none;
  background: transparent;
  cursor: pointer;
  --scale-track: linear-gradient(
    to right,
    var(--q-primary) 0%,
    var(--q-primary) var(--scale-fill, 20%),
    color-mix(in srgb, var(--q-muted-foreground) 22%, transparent)
      var(--scale-fill, 20%),
    color-mix(in srgb, var(--q-muted-foreground) 22%, transparent) 100%
  );
}

.scale-slider:focus-visible {
  outline: none;
}

.scale-slider::-webkit-slider-runnable-track {
  height: 4px;
  border-radius: 999px;
  background: var(--scale-track);
}

.scale-slider::-webkit-slider-thumb {
  appearance: none;
  width: 16px;
  height: 16px;
  margin-top: -6px;
  border-radius: 999px;
  border: 2px solid color-mix(in srgb, var(--q-surface) 70%, transparent);
  background: var(--q-primary);
  box-shadow: 0 1px 3px color-mix(in srgb, #000 18%, transparent);
  transition:
    transform var(--q-motion-fast) var(--q-motion-ease),
    box-shadow var(--q-motion-standard) var(--q-motion-ease);
}

.scale-slider:hover::-webkit-slider-thumb {
  transform: scale(1.06);
  box-shadow:
    0 0 0 6px color-mix(in srgb, var(--q-primary) 12%, transparent),
    0 1px 4px color-mix(in srgb, #000 16%, transparent);
}

.scale-slider:active::-webkit-slider-thumb {
  transform: scale(1.1);
  box-shadow:
    0 0 0 8px color-mix(in srgb, var(--q-primary) 14%, transparent),
    0 1px 3px color-mix(in srgb, #000 14%, transparent);
}

.scale-slider:focus-visible::-webkit-slider-thumb {
  box-shadow:
    0 0 0 6px color-mix(in srgb, var(--q-primary) 18%, transparent),
    0 1px 3px color-mix(in srgb, #000 16%, transparent);
}

.scale-slider::-moz-range-track {
  height: 4px;
  border-radius: 999px;
  background: var(--scale-track);
}

.scale-slider::-moz-range-thumb {
  width: 16px;
  height: 16px;
  border-radius: 999px;
  border: 2px solid color-mix(in srgb, var(--q-surface) 70%, transparent);
  background: var(--q-primary);
  box-shadow: 0 1px 3px color-mix(in srgb, #000 18%, transparent);
  transition:
    transform var(--q-motion-fast) var(--q-motion-ease),
    box-shadow var(--q-motion-standard) var(--q-motion-ease);
}

.scale-pct {
  flex: 0 0 44px;
  width: 44px;
  text-align: right;
  font-size: 13px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  color: var(--q-foreground);
}
</style>
