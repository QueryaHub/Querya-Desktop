<script setup lang="ts">
import { computed } from "vue";
import { storeToRefs } from "pinia";
import { useShellStore } from "../stores/shell";
import { useShellStatusStore } from "../stores/shellStatus";
import QueryaDivider from "./QueryaDivider.vue";

const shell = useShellStore();
const status = useShellStatusStore();
const {
  connectionName,
  connectionHost,
  isBusy,
  statusMessage,
  rowCount,
  columnCount,
  lastQueryMs,
  isReadOnly,
} = storeToRefs(status);

const connected = computed(() => !!connectionName.value);

const durationLabel = computed(() => {
  if (lastQueryMs.value == null) return null;
  if (lastQueryMs.value < 1000) return `${lastQueryMs.value} ms`;
  return `${(lastQueryMs.value / 1000).toFixed(2)} s`;
});

const countsLabel = computed(() => {
  if (rowCount.value == null && columnCount.value == null) return null;
  const r = rowCount.value ?? "—";
  const c = columnCount.value ?? "—";
  return `${r} × ${c}`;
});
</script>

<template>
  <footer class="status-bar" data-testid="status-bar">
    <div class="left">
      <button
        type="button"
        class="icon-btn"
        data-testid="status-sidebar-toggle"
        :aria-pressed="shell.sidebarOpen"
        :title="shell.sidebarOpen ? 'Hide sidebar (Ctrl+B)' : 'Show sidebar (Ctrl+B)'"
        @click="shell.toggleSidebar()"
      >
        ▤
      </button>
      <QueryaDivider vertical />
      <span
        class="dot"
        :class="{ on: connected }"
        aria-hidden="true"
      />
      <template v-if="connected">
        <span class="name">{{ connectionName }}</span>
        <span v-if="connectionHost" class="host">{{ connectionHost }}</span>
        <span v-if="isReadOnly" class="badge">RO</span>
      </template>
      <span v-else class="muted">No connection</span>
      <span v-if="isBusy" class="busy" aria-live="polite">Working…</span>
      <span v-else-if="statusMessage" class="msg">{{ statusMessage }}</span>
    </div>
    <div class="right">
      <span v-if="durationLabel" class="mono">{{ durationLabel }}</span>
      <span v-if="countsLabel" class="mono">{{ countsLabel }}</span>
    </div>
  </footer>
</template>

<style scoped>
.status-bar {
  flex: 0 0 var(--q-statusbar-h);
  height: var(--q-statusbar-h);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--q-space-3);
  padding: 0 10px;
  background: var(--q-surface);
  border-top: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  font-size: 11px;
  color: var(--q-foreground);
  user-select: none;
  z-index: 15;
}

.left,
.right {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.left {
  flex: 1;
}

.right {
  flex: 0 0 auto;
}

.icon-btn {
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  width: 18px;
  height: 18px;
  border-radius: 3px;
  cursor: pointer;
  font-size: 12px;
  line-height: 1;
  padding: 0;
}

.icon-btn[aria-pressed="true"] {
  color: var(--q-primary);
}

.icon-btn:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.dot {
  width: 7px;
  height: 7px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--q-muted-foreground) 40%, transparent);
  flex: 0 0 auto;
}

.dot.on {
  background: var(--q-success);
}

.name {
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 10rem;
}

.host,
.muted,
.msg,
.busy {
  color: var(--q-muted-foreground);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.badge {
  font-size: 10px;
  font-weight: 600;
  padding: 0 4px;
  border-radius: 3px;
  background: var(--q-accent);
  color: var(--q-muted-foreground);
}

.mono {
  font-family: var(--q-font-mono);
  color: var(--q-muted-foreground);
  font-variant-numeric: tabular-nums;
}
</style>
