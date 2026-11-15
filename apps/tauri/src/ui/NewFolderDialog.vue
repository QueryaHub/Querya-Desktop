<script setup lang="ts">
import { nextTick, ref, watch } from "vue";

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{
  close: [];
  create: [name: string];
}>();

const name = ref("");
const error = ref<string | null>(null);
const input = ref<HTMLInputElement | null>(null);

watch(
  () => props.open,
  async (v) => {
    if (!v) return;
    name.value = "";
    error.value = null;
    await nextTick();
    input.value?.focus();
  },
);

function submit() {
  const trimmed = name.value.trim();
  if (!trimmed) {
    error.value = "Enter a folder name";
    return;
  }
  emit("create", trimmed);
  emit("close");
}

function onKey(e: KeyboardEvent) {
  if (e.key === "Escape") {
    e.preventDefault();
    emit("close");
  } else if (e.key === "Enter") {
    e.preventDefault();
    submit();
  }
}
</script>

<template>
  <div
    v-if="open"
    class="overlay"
    data-testid="new-folder-dialog"
    @click.self="emit('close')"
    @keydown="onKey"
  >
    <div class="dialog" role="dialog" aria-modal="true" aria-label="New folder">
      <h2>New folder</h2>
      <p class="hint">Group connections in the SERVERS tree.</p>
      <label class="field">
        <span>Name</span>
        <input
          ref="input"
          v-model="name"
          type="text"
          placeholder="e.g. Production"
          maxlength="64"
        />
      </label>
      <p v-if="error" class="err">{{ error }}</p>
      <footer>
        <button type="button" class="btn" @click="emit('close')">Cancel</button>
        <button type="button" class="btn primary" @click="submit">Create</button>
      </footer>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 2100;
  display: grid;
  place-items: center;
  background: color-mix(in srgb, #000 40%, transparent);
}

.dialog {
  width: min(360px, 92vw);
  padding: 18px 18px 14px;
  border-radius: 12px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  color: var(--q-foreground);
  box-shadow: 0 12px 40px color-mix(in srgb, #000 30%, transparent);
}

h2 {
  margin: 0 0 4px;
  font-size: 15px;
  font-weight: 650;
}

.hint {
  margin: 0 0 14px;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.field {
  display: flex;
  flex-direction: column;
  gap: 6px;
  font-size: 12px;
}

.field input {
  height: 32px;
  border-radius: 6px;
  border: 1px solid var(--q-border);
  background: var(--q-sidebar-bg);
  color: var(--q-foreground);
  padding: 0 10px;
  font: inherit;
}

.err {
  margin: 8px 0 0;
  font-size: 12px;
  color: var(--q-destructive);
}

footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 16px;
}

.btn {
  appearance: none;
  height: 30px;
  padding: 0 12px;
  border-radius: 6px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  color: var(--q-foreground);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}

.btn.primary {
  background: var(--q-primary);
  border-color: transparent;
  color: var(--q-primary-foreground);
}
</style>
