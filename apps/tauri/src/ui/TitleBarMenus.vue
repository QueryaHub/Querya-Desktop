<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";

const emit = defineEmits<{
  newConnection: [];
  newConnectionFromUrl: [];
  openSqlite: [];
  openPreferences: [];
  toggleSidebar: [];
  openTour: [];
  launchDemo: [];
}>();

type MenuId = "file" | "edit" | "view" | "connection" | "help" | null;

const openMenu = ref<MenuId>(null);

function toggle(id: Exclude<MenuId, null>) {
  openMenu.value = openMenu.value === id ? null : id;
}

function close() {
  openMenu.value = null;
}

function act(fn: () => void) {
  close();
  fn();
}

function onDoc(e: PointerEvent) {
  if (!openMenu.value) return;
  const t = e.target;
  if (t instanceof Element && t.closest("[data-menubar]")) return;
  close();
}

function onKey(e: KeyboardEvent) {
  if (e.key === "Escape") close();
}

onMounted(() => {
  window.addEventListener("pointerdown", onDoc, true);
  window.addEventListener("keydown", onKey, true);
});
onUnmounted(() => {
  window.removeEventListener("pointerdown", onDoc, true);
  window.removeEventListener("keydown", onKey, true);
});
</script>

<template>
  <nav class="menubar" data-menubar data-testid="title-menubar" data-no-drag>
    <div class="slot">
      <button
        type="button"
        class="top"
        :aria-expanded="openMenu === 'file'"
        @click="toggle('file')"
      >
        File
      </button>
      <div v-if="openMenu === 'file'" class="drop" role="menu">
        <button type="button" role="menuitem" @click="act(() => emit('openSqlite'))">
          Open SQLite File…
        </button>
        <button type="button" role="menuitem" disabled>Open Recent</button>
      </div>
    </div>

    <div class="slot">
      <button
        type="button"
        class="top"
        :aria-expanded="openMenu === 'edit'"
        @click="toggle('edit')"
      >
        Edit
      </button>
      <div v-if="openMenu === 'edit'" class="drop" role="menu">
        <button
          type="button"
          role="menuitem"
          data-testid="menu-preferences"
          @click="act(() => emit('openPreferences'))"
        >
          Preferences…
        </button>
      </div>
    </div>

    <div class="slot">
      <button
        type="button"
        class="top"
        :aria-expanded="openMenu === 'view'"
        @click="toggle('view')"
      >
        View
      </button>
      <div v-if="openMenu === 'view'" class="drop" role="menu">
        <button
          type="button"
          role="menuitem"
          @click="act(() => emit('toggleSidebar'))"
        >
          Toggle Sidebar
        </button>
      </div>
    </div>

    <div class="slot">
      <button
        type="button"
        class="top"
        :aria-expanded="openMenu === 'connection'"
        @click="toggle('connection')"
      >
        Connection
      </button>
      <div v-if="openMenu === 'connection'" class="drop" role="menu">
        <button
          type="button"
          role="menuitem"
          data-testid="menu-new-connection"
          @click="act(() => emit('newConnection'))"
        >
          New Database Connection
        </button>
        <button
          type="button"
          role="menuitem"
          @click="act(() => emit('newConnectionFromUrl'))"
        >
          New Connection from URL…
        </button>
        <button
          type="button"
          role="menuitem"
          @click="act(() => emit('launchDemo'))"
        >
          Demo Playground
        </button>
      </div>
    </div>

    <div class="slot">
      <button
        type="button"
        class="top"
        :aria-expanded="openMenu === 'help'"
        @click="toggle('help')"
      >
        Help
      </button>
      <div v-if="openMenu === 'help'" class="drop" role="menu">
        <button type="button" role="menuitem" @click="act(() => emit('openTour'))">
          Welcome Tour
        </button>
      </div>
    </div>
  </nav>
</template>

<style scoped>
.menubar {
  display: inline-flex;
  align-items: center;
  gap: 0;
  height: 100%;
}

.slot {
  position: relative;
  height: 100%;
  display: flex;
  align-items: center;
}

.top {
  appearance: none;
  border: 0;
  background: transparent;
  height: 22px;
  padding: 0 8px;
  border-radius: 4px;
  font: inherit;
  font-size: 12px;
  color: var(--q-foreground);
  cursor: default;
}

.top:hover,
.top[aria-expanded="true"] {
  background: var(--q-accent);
}

.drop {
  position: absolute;
  top: calc(100% - 2px);
  left: 0;
  z-index: 50;
  min-width: 220px;
  padding: 4px;
  border-radius: var(--q-radius-control);
  background: var(--q-surface);
  border: 1px solid var(--q-border);
  box-shadow: 0 10px 28px color-mix(in srgb, #000 40%, transparent);
}

.drop button {
  appearance: none;
  border: 0;
  background: transparent;
  width: 100%;
  text-align: left;
  padding: 6px 10px;
  border-radius: var(--q-radius-sm);
  font: inherit;
  font-size: 12px;
  color: var(--q-foreground);
  cursor: pointer;
}

.drop button:hover:not(:disabled) {
  background: var(--q-accent);
}

.drop button:disabled {
  opacity: 0.4;
  cursor: default;
}
</style>
