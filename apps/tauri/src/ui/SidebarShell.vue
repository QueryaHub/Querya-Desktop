<script setup lang="ts">
import { computed, onUnmounted, ref } from "vue";
import { useShellStore } from "../stores/shell";
import { useQueryaMotion } from "../motion";

const shell = useShellStore();
const motion = useQueryaMotion();
const dragging = ref(false);

const panelStyle = computed(() => ({
  width: shell.sidebarOpen ? `${shell.sidebarWidth}px` : "0px",
  transitionProperty: dragging.value ? "none" : "width",
  transitionDuration: `${motion.duration("sidebarCubic")}ms`,
  transitionTimingFunction: motion.easing("standard"),
}));

function onResizeStart(e: PointerEvent) {
  if (!shell.sidebarOpen) return;
  e.preventDefault();
  dragging.value = true;
  const startX = e.clientX;
  const startW = shell.sidebarWidth;

  const onMove = (ev: PointerEvent) => {
    shell.setSidebarWidth(startW + (ev.clientX - startX));
  };
  const onUp = () => {
    dragging.value = false;
    window.removeEventListener("pointermove", onMove);
    window.removeEventListener("pointerup", onUp);
  };
  window.addEventListener("pointermove", onMove);
  window.addEventListener("pointerup", onUp);
}

onUnmounted(() => {
  dragging.value = false;
});
</script>

<template>
  <aside
    class="sidebar"
    data-testid="sidebar-shell"
    :class="{ open: shell.sidebarOpen, dragging }"
    :style="panelStyle"
    :aria-hidden="!shell.sidebarOpen"
  >
    <div class="inner q-glass">
      <div class="head">
        <span class="label">Connections</span>
        <button
          type="button"
          class="icon-btn"
          aria-label="Collapse sidebar"
          @click="shell.setSidebarOpen(false)"
        >
          ⟨
        </button>
      </div>
      <div class="body">
        <p class="empty">No connections yet</p>
        <p class="hint">SQLite / Postgres land in later issues</p>
      </div>
    </div>
    <div
      class="resizer"
      role="separator"
      aria-orientation="vertical"
      aria-label="Resize sidebar"
      @pointerdown="onResizeStart"
    />
  </aside>
</template>

<style scoped>
.sidebar {
  position: relative;
  flex: 0 0 auto;
  height: 100%;
  min-width: 0;
  overflow: hidden;
}

.inner {
  height: 100%;
  display: flex;
  flex-direction: column;
  border-radius: 0;
  border-top: 0;
  border-bottom: 0;
  border-left: 0;
  min-width: 180px;
}

.head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--q-space-2);
  padding: var(--q-space-3) var(--q-space-3) var(--q-space-2);
  border-bottom: 1px solid var(--q-border);
}

.label {
  font-size: var(--q-text-xs);
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--q-muted-foreground);
}

.icon-btn {
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--q-muted-foreground);
  width: 1.75rem;
  height: 1.75rem;
  border-radius: var(--q-radius-sm);
  cursor: pointer;
}

.icon-btn:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.body {
  flex: 1;
  padding: var(--q-space-4) var(--q-space-3);
}

.empty {
  margin: 0;
  font-size: var(--q-text-sm);
  color: var(--q-foreground);
}

.hint {
  margin: var(--q-space-1) 0 0;
  font-size: var(--q-text-xs);
  color: var(--q-muted-foreground);
}

.resizer {
  position: absolute;
  top: 0;
  right: 0;
  width: 5px;
  height: 100%;
  cursor: col-resize;
  z-index: 2;
}

.resizer:hover,
.dragging .resizer {
  background: color-mix(in srgb, var(--q-primary) 35%, transparent);
}
</style>
