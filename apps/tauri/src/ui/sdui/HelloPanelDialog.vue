<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from "vue";
import {
  extHostCall,
  extHostStop,
  mountHelloPanel,
} from "../../api/extensions";
import {
  type SduiActionEvent,
  type SduiPanelNode,
} from "../../sdui";
import QueryaButton from "../QueryaButton.vue";
import SduiPanelRenderer from "./SduiPanelRenderer.vue";

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

const loading = ref(false);
const error = ref<string | null>(null);
const descriptor = ref<SduiPanelNode | null>(null);
const sessionId = ref<string | null>(null);
const lastAction = ref<string | null>(null);

async function teardown() {
  const id = sessionId.value;
  sessionId.value = null;
  descriptor.value = null;
  if (id) {
    await extHostStop(id).catch(() => undefined);
  }
}

async function boot() {
  loading.value = true;
  error.value = null;
  lastAction.value = null;
  try {
    const mounted = await mountHelloPanel();
    sessionId.value = mounted.sessionId;
    descriptor.value = mounted.descriptor;
  } catch (err) {
    error.value = err instanceof Error ? err.message : String(err);
    await teardown();
  } finally {
    loading.value = false;
  }
}

watch(
  () => props.open,
  async (open) => {
    if (open) await boot();
    else await teardown();
  },
);

async function onAction(e: SduiActionEvent) {
  lastAction.value = `${e.nodeId}:${e.action}`;
  if (e.action === "ping" && sessionId.value) {
    try {
      const pong = await extHostCall(sessionId.value, "system.ping");
      lastAction.value = `system.ping → ${JSON.stringify(pong)}`;
    } catch (err) {
      lastAction.value = err instanceof Error ? err.message : String(err);
    }
    return;
  }
  if (e.action === "dismiss") {
    emit("close");
  }
}

function onKey(e: KeyboardEvent) {
  if (!props.open) return;
  if (e.key === "Escape") {
    e.preventDefault();
    emit("close");
  }
}

onMounted(() => window.addEventListener("keydown", onKey));
onUnmounted(() => {
  window.removeEventListener("keydown", onKey);
  void teardown();
});
</script>

<template>
  <div
    v-if="open"
    class="overlay q-modal-scrim"
    data-testid="hello-panel-dialog"
    @click.self="emit('close')"
  >
    <div
      class="shell q-glass"
      role="dialog"
      aria-modal="true"
      aria-label="Hello panel extension"
    >
      <p class="eyebrow">Extension · querya.hello-panel</p>
      <p v-if="loading" class="status">Starting extension…</p>
      <p v-else-if="error" class="status status--error" data-testid="hello-panel-error">
        {{ error }}
      </p>
      <SduiPanelRenderer
        v-else-if="descriptor"
        :descriptor="descriptor"
        @action="onAction"
      />
      <p v-if="lastAction" class="trace" data-testid="hello-panel-last-action">
        {{ lastAction }}
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

.status {
  margin: 0;
  font-size: 13px;
}

.status--error {
  color: var(--q-danger, #e35d6a);
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
