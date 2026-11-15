<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";

export type CtxItem = {
  id: string;
  label: string;
  disabled?: boolean;
  children?: CtxItem[];
};

const props = defineProps<{
  open: boolean;
  x: number;
  y: number;
  items: CtxItem[];
}>();

const emit = defineEmits<{
  close: [];
  select: [id: string];
}>();

const root = ref<HTMLDivElement | null>(null);
const submenu = ref<string | null>(null);

const style = computed(() => ({
  left: `${props.x}px`,
  top: `${props.y}px`,
}));

function onSelect(item: CtxItem) {
  if (item.disabled) return;
  if (item.children?.length) {
    submenu.value = submenu.value === item.id ? null : item.id;
    return;
  }
  emit("select", item.id);
  emit("close");
}

function onDocPointer(e: PointerEvent) {
  if (!props.open) return;
  const el = root.value;
  if (el && e.target instanceof Node && el.contains(e.target)) return;
  emit("close");
}

function onKey(e: KeyboardEvent) {
  if (!props.open) return;
  if (e.key === "Escape") {
    e.preventDefault();
    emit("close");
  }
}

watch(
  () => props.open,
  async (v) => {
    submenu.value = null;
    if (v) await nextTick();
  },
);

onMounted(() => {
  window.addEventListener("pointerdown", onDocPointer, true);
  window.addEventListener("keydown", onKey, true);
});
onUnmounted(() => {
  window.removeEventListener("pointerdown", onDocPointer, true);
  window.removeEventListener("keydown", onKey, true);
});
</script>

<template>
  <div
    v-if="open"
    ref="root"
    class="ctx"
    data-testid="querya-context-menu"
    :style="style"
    role="menu"
  >
    <div v-for="item in items" :key="item.id" class="row">
      <button
        type="button"
        class="item"
        role="menuitem"
        :disabled="item.disabled"
        :aria-haspopup="item.children ? 'menu' : undefined"
        :aria-expanded="item.children ? submenu === item.id : undefined"
        @click="onSelect(item)"
        @mouseenter="item.children ? (submenu = item.id) : (submenu = null)"
      >
        <span>{{ item.label }}</span>
        <span v-if="item.children" class="caret">▸</span>
      </button>
      <div
        v-if="item.children && submenu === item.id"
        class="sub"
        role="menu"
      >
        <button
          v-for="child in item.children"
          :key="child.id"
          type="button"
          class="item"
          role="menuitem"
          :disabled="child.disabled"
          @click="onSelect(child)"
        >
          {{ child.label }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.ctx {
  position: fixed;
  z-index: 1000;
  min-width: 168px;
  padding: 4px;
  border-radius: var(--q-radius-control);
  background: var(--q-surface);
  border: 1px solid var(--q-border);
  box-shadow: 0 10px 28px color-mix(in srgb, #000 40%, transparent);
}

.row {
  position: relative;
}

.item {
  appearance: none;
  border: 0;
  background: transparent;
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  text-align: left;
  padding: 6px 10px;
  border-radius: var(--q-radius-sm);
  font: inherit;
  font-size: 12px;
  color: var(--q-foreground);
  cursor: pointer;
}

.item:hover:not(:disabled) {
  background: var(--q-accent);
}

.item:disabled {
  opacity: 0.4;
  cursor: default;
}

.caret {
  color: var(--q-muted-foreground);
  font-size: 10px;
}

.sub {
  position: absolute;
  left: calc(100% - 4px);
  top: -4px;
  min-width: 160px;
  padding: 4px;
  border-radius: var(--q-radius-control);
  background: var(--q-surface);
  border: 1px solid var(--q-border);
  box-shadow: 0 10px 28px color-mix(in srgb, #000 40%, transparent);
}
</style>
