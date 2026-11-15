<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import {
  filterCommands,
  type AppCommand,
} from "../commands/registry";

const props = defineProps<{
  open: boolean;
  commands: AppCommand[];
}>();

const emit = defineEmits<{ close: [] }>();

const query = ref("");
const selected = ref(0);
const input = ref<HTMLInputElement | null>(null);

const hits = computed(() => filterCommands(props.commands, query.value));

watch(
  () => props.open,
  async (v) => {
    if (!v) return;
    query.value = "";
    selected.value = 0;
    await nextTick();
    input.value?.focus();
  },
);

watch(hits, () => {
  selected.value = 0;
});

function runSelected() {
  const cmd = hits.value[selected.value];
  if (!cmd) return;
  emit("close");
  cmd.run();
}

function onKey(e: KeyboardEvent) {
  if (!props.open) return;
  if (e.key === "Escape") {
    e.preventDefault();
    emit("close");
  } else if (e.key === "ArrowDown") {
    e.preventDefault();
    selected.value = Math.min(selected.value + 1, hits.value.length - 1);
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    selected.value = Math.max(selected.value - 1, 0);
  } else if (e.key === "Enter") {
    e.preventDefault();
    runSelected();
  }
}

onMounted(() => window.addEventListener("keydown", onKey, true));
onUnmounted(() => window.removeEventListener("keydown", onKey, true));
</script>

<template>
  <div
    v-if="open"
    class="overlay"
    data-testid="command-palette"
    @click.self="emit('close')"
  >
    <div class="palette q-glass" role="dialog" aria-label="Command palette">
      <input
        ref="input"
        v-model="query"
        class="query"
        type="search"
        placeholder="Type a command…"
        aria-label="Filter commands"
      />
      <ul class="list" role="listbox">
        <li v-if="!hits.length" class="empty">No matching commands</li>
        <li
          v-for="(cmd, i) in hits"
          :key="cmd.id"
          role="option"
          class="item"
          :class="{ on: i === selected }"
          :aria-selected="i === selected"
          @mouseenter="selected = i"
          @click="runSelected()"
        >
          <span class="title">{{ cmd.title }}</span>
          <span v-if="cmd.subtitle" class="sub">{{ cmd.subtitle }}</span>
        </li>
      </ul>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 2100;
  display: grid;
  place-items: start center;
  padding-top: 12vh;
  background: color-mix(in srgb, #000 40%, transparent);
}

.palette {
  width: min(560px, 92vw);
  border-radius: 12px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  overflow: hidden;
  box-shadow: 0 18px 48px color-mix(in srgb, #000 45%, transparent);
}

.query {
  width: 100%;
  height: 44px;
  border: 0;
  border-bottom: 1px solid
    color-mix(in srgb, var(--q-border) 70%, transparent);
  background: transparent;
  color: var(--q-foreground);
  padding: 0 16px;
  font: inherit;
  font-size: 14px;
  outline: none;
}

.list {
  list-style: none;
  margin: 0;
  padding: 6px;
  max-height: 320px;
  overflow: auto;
}

.item {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  padding: 8px 10px;
  border-radius: var(--q-radius-control);
  cursor: pointer;
  font-size: 13px;
}

.item.on,
.item:hover {
  background: color-mix(in srgb, var(--q-primary) 16%, transparent);
}

.title {
  color: var(--q-foreground);
  font-weight: 500;
}

.sub {
  font-size: 11px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.empty {
  padding: 16px;
  text-align: center;
  color: var(--q-muted-foreground);
  font-size: 12px;
}
</style>
