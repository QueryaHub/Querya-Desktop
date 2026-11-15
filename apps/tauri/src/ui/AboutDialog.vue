<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from "vue";
import { invoke } from "@tauri-apps/api/core";
import QueryaButton from "./QueryaButton.vue";

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

const version = ref("…");
const stack = ref("tauri2-vue3");

watch(
  () => props.open,
  async (v) => {
    if (!v) return;
    try {
      const info = await invoke<{ version: string; stack: string }>("app_info");
      version.value = info.version;
      stack.value = info.stack;
    } catch {
      version.value = "0.1.0";
    }
  },
);

function onKey(e: KeyboardEvent) {
  if (!props.open) return;
  if (e.key === "Escape") {
    e.preventDefault();
    emit("close");
  }
}

onMounted(() => window.addEventListener("keydown", onKey));
onUnmounted(() => window.removeEventListener("keydown", onKey));
</script>

<template>
  <div
    v-if="open"
    class="overlay q-modal-scrim"
    data-testid="about-dialog"
    @click.self="emit('close')"
  >
    <div class="card q-glass" role="dialog" aria-modal="true" aria-label="About Querya">
      <span class="mark" aria-hidden="true" />
      <h2>Querya</h2>
      <p class="ver">Version {{ version }}</p>
      <p class="desc">A lightweight desktop SQL/NoSQL client.</p>
      <p class="meta">{{ stack }} · Fluid + Liquid Glass · MIT License</p>
      <QueryaButton variant="primary" size="md" @click="emit('close')">
        OK
      </QueryaButton>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 2200;
  display: grid;
  place-items: center;
  padding: 24px;
}

.card {
  width: min(380px, 100%);
  border-radius: 14px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  padding: 28px 24px 20px;
  text-align: center;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
}

.mark {
  width: 48px;
  height: 48px;
  border-radius: 999px;
  background: var(--q-primary);
  box-shadow: 0 0 0 4px color-mix(in srgb, var(--q-primary) 25%, transparent);
  margin-bottom: 6px;
}

h2 {
  margin: 0;
  font-size: 20px;
  font-weight: 650;
}

.ver,
.desc,
.meta {
  margin: 0;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.meta {
  font-family: var(--q-font-mono);
  font-size: 11px;
  margin-top: 4px;
}

.card :deep(.q-btn) {
  margin-top: 12px;
  min-width: 88px;
}
</style>
