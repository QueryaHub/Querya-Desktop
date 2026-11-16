<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
import {
  SAMPLE_HELLO_PANEL_DESCRIPTOR,
  type SduiActionEvent,
} from "../../sdui";
import QueryaButton from "../QueryaButton.vue";
import SduiPanelRenderer from "./SduiPanelRenderer.vue";

defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

const lastAction = ref<string | null>(null);

function onAction(e: SduiActionEvent) {
  lastAction.value = `${e.nodeId}:${e.action}`;
  if (e.action === "dismiss") emit("close");
}

function onKey(e: KeyboardEvent) {
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
    data-testid="sdui-sample-dialog"
    @click.self="emit('close')"
  >
    <div class="shell q-glass" role="dialog" aria-modal="true" aria-label="SDUI sample panel">
      <p class="eyebrow">SDUI preview</p>
      <SduiPanelRenderer
        :descriptor="SAMPLE_HELLO_PANEL_DESCRIPTOR"
        @action="onAction"
      />
      <p v-if="lastAction" class="trace" data-testid="sdui-last-action">
        Last action: {{ lastAction }}
      </p>
      <div class="footer">
        <QueryaButton variant="ghost" size="sm" @click="emit('close')">
          Close
        </QueryaButton>
      </div>
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

.shell {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 20px;
  border-radius: 14px;
  border: 1px solid var(--q-border);
  background: var(--q-bg, var(--q-surface));
  width: min(520px, 100%);
}

.eyebrow {
  margin: 0;
  font-size: 11px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--q-fg-muted, var(--q-muted, #8b909a));
}

.trace {
  margin: 0;
  font-size: 12px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  color: var(--q-fg-muted, var(--q-muted, #8b909a));
}

.footer {
  display: flex;
  justify-content: flex-end;
}
</style>
