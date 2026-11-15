<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import {
  applyTheme,
  readStoredTheme,
  type QueryaThemeMode,
} from "../theme/queryaTheme";
import { useQueryaMotion } from "../motion";
import { usePreferencesStore } from "../stores/preferences";
import type { QueryaMotionLevel } from "../motion/types";

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

type Category =
  | "general"
  | "appearance"
  | "sql"
  | "dataGrid"
  | "extensions"
  | "mcp"
  | "shortcuts"
  | "about";

const categories: {
  id: Category;
  label: string;
  description: string;
}[] = [
  {
    id: "general",
    label: "General",
    description: "Startup, updates, release channel",
  },
  {
    id: "appearance",
    label: "Appearance",
    description: "Themes, dark mode, scaling, animations",
  },
  {
    id: "sql",
    label: "SQL & Editor",
    description: "Editor font, statement timeouts, query history",
  },
  {
    id: "dataGrid",
    label: "Data Grid",
    description: "Result rows limit, column sizing, safety",
  },
  {
    id: "extensions",
    label: "Extensions",
    description: "Sideloading .qext/.zip packages, extension folder",
  },
  {
    id: "mcp",
    label: "MCP Server",
    description: "Let AI clients read shared connections",
  },
  {
    id: "shortcuts",
    label: "Shortcuts",
    description: "Keyboard shortcuts reference and keymap",
  },
  {
    id: "about",
    label: "About & Storage",
    description: "App version, local storage, paths",
  },
];

const category = ref<Category>("general");
const search = ref("");
const themeMode = ref<QueryaThemeMode>(readStoredTheme());
const prefs = usePreferencesStore();
const motion = useQueryaMotion();

const filteredCategories = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return categories;
  return categories.filter(
    (c) =>
      c.label.toLowerCase().includes(q) ||
      c.description.toLowerCase().includes(q) ||
      c.id.toLowerCase().includes(q),
  );
});

const activeMeta = computed(
  () => categories.find((c) => c.id === category.value) ?? categories[0],
);

const shortcuts = [
  { keys: "Ctrl/Cmd + N", action: "New connection" },
  { keys: "Ctrl/Cmd + B", action: "Toggle sidebar" },
  { keys: "Ctrl/Cmd + ,", action: "Preferences" },
  { keys: "Ctrl/Cmd + Enter", action: "Run SQL (SQL tab)" },
  { keys: "Esc", action: "Close dialog / menu" },
];

function setTheme(mode: QueryaThemeMode) {
  themeMode.value = mode;
  applyTheme(mode);
}

function setMotion(level: QueryaMotionLevel) {
  motion.setLevel(level);
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
  (v) => {
    if (v) {
      category.value = "general";
      search.value = "";
      themeMode.value = readStoredTheme();
    }
  },
);

watch(filteredCategories, (list) => {
  if (!list.some((c) => c.id === category.value) && list[0]) {
    category.value = list[0].id;
  }
});

onMounted(() => window.addEventListener("keydown", onKey));
onUnmounted(() => window.removeEventListener("keydown", onKey));
</script>

<template>
  <div
    v-if="open"
    class="overlay"
    data-testid="preferences-dialog"
    @click.self="emit('close')"
  >
    <div
      class="dialog q-glass"
      role="dialog"
      aria-modal="true"
      :aria-label="activeMeta.label"
    >
      <aside class="nav">
        <p class="nav-title">Preferences</p>
        <input
          v-model="search"
          class="search"
          type="search"
          placeholder="Filter…"
          aria-label="Filter preferences"
        />
        <button
          v-for="c in filteredCategories"
          :key="c.id"
          type="button"
          class="nav-item"
          :class="{ active: category === c.id }"
          @click="category = c.id"
        >
          <span class="nav-label">{{ c.label }}</span>
          <span class="nav-desc">{{ c.description }}</span>
        </button>
      </aside>

      <section class="pane">
        <header class="pane-head">
          <div>
            <h2>{{ activeMeta.label }}</h2>
            <p class="pane-sub">{{ activeMeta.description }}</p>
          </div>
          <button
            type="button"
            class="x"
            aria-label="Close"
            @click="emit('close')"
          >
            ✕
          </button>
        </header>

        <!-- General -->
        <div v-if="category === 'general'" class="body">
          <h3>General Settings</h3>
          <p class="hint">
            Application startup behavior and update release channels.
          </p>
          <label class="switch-row">
            <div>
              <span class="t">Check for updates automatically on startup</span>
              <span class="s"
                >Silently checks for new releases when Querya starts.</span
              >
            </div>
            <input v-model="prefs.state.checkUpdatesOnStartup" type="checkbox" />
          </label>
          <label class="field">
            <span class="t">Release channel</span>
            <span class="s"
              >Stable receives tested updates. Beta gets early builds.</span
            >
            <select v-model="prefs.state.updateChannel">
              <option value="stable">Stable (Recommended)</option>
              <option value="dev">Beta / Early Access</option>
            </select>
          </label>
          <label class="switch-row">
            <div>
              <span class="t">Confirm destructive queries</span>
              <span class="s"
                >Ask before running DROP / DELETE / TRUNCATE without WHERE.</span
              >
            </div>
            <input v-model="prefs.state.confirmDestructive" type="checkbox" />
          </label>
        </div>

        <!-- Appearance -->
        <div v-else-if="category === 'appearance'" class="body">
          <h3>Appearance</h3>
          <p class="hint">Themes, dark mode, and Fluid Motion.</p>
          <div class="block">
            <span class="t">Color mode</span>
            <div class="seg">
              <button
                type="button"
                :class="{ on: themeMode === 'system' }"
                @click="setTheme('system')"
              >
                System
              </button>
              <button
                type="button"
                :class="{ on: themeMode === 'light' }"
                @click="setTheme('light')"
              >
                Light
              </button>
              <button
                type="button"
                :class="{ on: themeMode === 'dark' }"
                @click="setTheme('dark')"
              >
                Dark
              </button>
            </div>
          </div>
          <div class="block">
            <span class="t">Fluid Motion</span>
            <span class="s"
              >Full / Reduced / Off — syncs with prefers-reduced-motion when
              following system.</span
            >
            <div class="seg">
              <button
                type="button"
                :class="{ on: motion.level.value === 'full' }"
                @click="setMotion('full')"
              >
                Full
              </button>
              <button
                type="button"
                :class="{ on: motion.level.value === 'reduced' }"
                @click="setMotion('reduced')"
              >
                Reduced
              </button>
              <button
                type="button"
                :class="{ on: motion.level.value === 'off' }"
                @click="setMotion('off')"
              >
                Off
              </button>
            </div>
            <button type="button" class="linkish" @click="motion.followSystem()">
              Follow system reduced-motion
            </button>
          </div>
          <p class="muted">
            Theme packs / import (VS Code JSON) land with the theme editor
            port.
          </p>
        </div>

        <!-- SQL -->
        <div v-else-if="category === 'sql'" class="body">
          <h3>SQL &amp; Query Execution</h3>
          <p class="hint">
            Global statement timeouts, editor formatting, and query history.
          </p>
          <label class="field">
            <span class="t">Editor font size</span>
            <select v-model.number="prefs.state.editorFontSize">
              <option :value="11">11 pt</option>
              <option :value="12">12 pt</option>
              <option :value="13">13 pt (Default)</option>
              <option :value="14">14 pt</option>
              <option :value="16">16 pt</option>
              <option :value="18">18 pt</option>
            </select>
          </label>
          <label class="field">
            <span class="t">PostgreSQL timeout (sec)</span>
            <input
              v-model.number="prefs.state.pgTimeoutSec"
              type="number"
              min="0"
              step="5"
            />
          </label>
          <label class="field">
            <span class="t">MySQL timeout (sec)</span>
            <input
              v-model.number="prefs.state.mysqlTimeoutSec"
              type="number"
              min="0"
              step="5"
            />
          </label>
          <label class="field">
            <span class="t">SQLite timeout (sec)</span>
            <input
              v-model.number="prefs.state.sqliteTimeoutSec"
              type="number"
              min="0"
              step="5"
            />
          </label>
          <label class="field">
            <span class="t">Query history limit</span>
            <input
              v-model.number="prefs.state.historyMax"
              type="number"
              min="10"
              step="10"
            />
          </label>
        </div>

        <!-- Data grid -->
        <div v-else-if="category === 'dataGrid'" class="body">
          <h3>Data Grid</h3>
          <p class="hint">Result rows limit and browse safety.</p>
          <label class="field">
            <span class="t">Max result rows</span>
            <span class="s"
              >SELECT results truncate after this many rows (Flutter default
              5000).</span
            >
            <input
              v-model.number="prefs.state.maxResultRows"
              type="number"
              min="100"
              step="100"
            />
          </label>
        </div>

        <!-- Extensions -->
        <div v-else-if="category === 'extensions'" class="body">
          <h3>Extensions</h3>
          <p class="hint">Sideloading packages and extension host folder.</p>
          <label class="switch-row">
            <div>
              <span class="t">Allow sideload (.qext / .zip)</span>
              <span class="s"
                >Install local extension packages outside the marketplace.</span
              >
            </div>
            <input v-model="prefs.state.extensionsSideload" type="checkbox" />
          </label>
          <p class="muted">Extension manager dialog ports with the marketplace epic.</p>
        </div>

        <!-- MCP -->
        <div v-else-if="category === 'mcp'" class="body">
          <h3>MCP Server</h3>
          <p class="hint">Let AI clients read shared connections.</p>
          <label class="switch-row">
            <div>
              <span class="t">Enable in-process MCP server</span>
              <span class="s"
                >Expose Querya tools to MCP-compatible assistants.</span
              >
            </div>
            <input v-model="prefs.state.mcpEnabled" type="checkbox" />
          </label>
          <p class="muted">Rust MCP host lands in the MCP epic — toggle is stored now.</p>
        </div>

        <!-- Shortcuts -->
        <div v-else-if="category === 'shortcuts'" class="body">
          <h3>Shortcuts</h3>
          <p class="hint">Keyboard reference (keymap customization later).</p>
          <table class="keys">
            <tbody>
              <tr v-for="row in shortcuts" :key="row.keys">
                <td class="mono">{{ row.keys }}</td>
                <td>{{ row.action }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- About -->
        <div v-else class="body">
          <h3>About &amp; Storage</h3>
          <p class="hint">Querya Desktop (Tauri 2 + Vue 3)</p>
          <dl class="dl">
            <div>
              <dt>Stack</dt>
              <dd>tauri2-vue3 · Fluid + Liquid Glass · no shadcn</dd>
            </div>
            <div>
              <dt>Prefs storage</dt>
              <dd class="mono">localStorage · querya.preferences.v1</dd>
            </div>
            <div>
              <dt>Theme</dt>
              <dd class="mono">querya.theme</dd>
            </div>
            <div>
              <dt>Motion</dt>
              <dd class="mono">querya.motion</dd>
            </div>
          </dl>
          <button type="button" class="danger" @click="prefs.reset()">
            Reset preferences to defaults
          </button>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 2000;
  display: grid;
  place-items: center;
  background: color-mix(in srgb, #000 45%, transparent);
  padding: 20px;
}

.dialog {
  width: min(860px, 100%);
  height: min(560px, 100%);
  display: grid;
  grid-template-columns: 220px 1fr;
  border-radius: 12px;
  overflow: hidden;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
}

.nav {
  padding: 12px 8px;
  background: var(--q-sidebar-bg);
  border-right: 1px solid
    color-mix(in srgb, var(--q-border) 70%, transparent);
  display: flex;
  flex-direction: column;
  gap: 2px;
  overflow: auto;
}

.nav-title {
  margin: 0 8px 8px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--q-muted-foreground);
}

.search {
  margin: 0 6px 8px;
  height: 28px;
  border: 1px solid var(--q-border);
  border-radius: var(--q-radius-control);
  background: var(--q-surface);
  color: var(--q-foreground);
  padding: 0 8px;
  font: inherit;
  font-size: 12px;
}

.nav-item {
  appearance: none;
  border: 0;
  background: transparent;
  text-align: left;
  padding: 8px 10px;
  border-radius: var(--q-radius-control);
  font: inherit;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.nav-item.active,
.nav-item:hover {
  background: color-mix(in srgb, var(--q-primary) 14%, transparent);
}

.nav-label {
  font-size: 12px;
  font-weight: 600;
  color: var(--q-foreground);
}

.nav-item.active .nav-label {
  color: var(--q-primary);
}

.nav-desc {
  font-size: 10px;
  color: var(--q-muted-foreground);
  line-height: 1.3;
}

.pane {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.pane-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  padding: 14px 16px;
  border-bottom: 1px solid
    color-mix(in srgb, var(--q-border) 70%, transparent);
}

.pane-head h2 {
  margin: 0;
  font-size: 15px;
  font-weight: 650;
}

.pane-sub {
  margin: 4px 0 0;
  font-size: 11px;
  color: var(--q-muted-foreground);
}

.x {
  appearance: none;
  border: 0;
  background: transparent;
  width: 28px;
  height: 28px;
  border-radius: var(--q-radius-sm);
  color: var(--q-muted-foreground);
  cursor: pointer;
  flex: 0 0 auto;
}

.x:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.body {
  padding: 16px 18px 20px;
  overflow: auto;
}

.body h3 {
  margin: 0 0 6px;
  font-size: 13px;
  font-weight: 650;
}

.hint {
  margin: 0 0 14px;
  font-size: 12px;
  color: var(--q-muted-foreground);
  line-height: 1.4;
}

.muted {
  margin: 12px 0 0;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.switch-row,
.field,
.block {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 10px 0;
  border-bottom: 1px solid
    color-mix(in srgb, var(--q-border) 35%, transparent);
}

.switch-row {
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.t {
  font-size: 12px;
  font-weight: 500;
  color: var(--q-foreground);
}

.s {
  display: block;
  font-size: 11px;
  color: var(--q-muted-foreground);
  line-height: 1.35;
  margin-top: 2px;
}

select,
input[type="number"] {
  height: 30px;
  max-width: 220px;
  border: 1px solid var(--q-border);
  border-radius: var(--q-radius-control);
  background: var(--q-sidebar-bg);
  color: var(--q-foreground);
  padding: 0 8px;
  font: inherit;
  font-size: 12px;
}

.seg {
  display: inline-flex;
  gap: 4px;
  padding: 3px;
  border-radius: var(--q-radius-control);
  background: var(--q-sidebar-bg);
  width: fit-content;
}

.seg button {
  appearance: none;
  border: 0;
  background: transparent;
  padding: 6px 12px;
  border-radius: var(--q-radius-sm);
  font: inherit;
  font-size: 12px;
  color: var(--q-muted-foreground);
  cursor: pointer;
}

.seg button.on {
  background: var(--q-surface);
  color: var(--q-foreground);
  font-weight: 600;
}

.linkish {
  appearance: none;
  border: 0;
  background: transparent;
  padding: 0;
  width: fit-content;
  font: inherit;
  font-size: 11px;
  color: var(--q-primary);
  cursor: pointer;
  text-align: left;
}

.keys {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}

.keys td {
  padding: 8px 0;
  border-bottom: 1px solid
    color-mix(in srgb, var(--q-border) 35%, transparent);
}

.mono {
  font-family: var(--q-font-mono);
  font-size: 11px;
  color: var(--q-muted-foreground);
}

.dl {
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.dl div {
  display: grid;
  grid-template-columns: 7rem 1fr;
  gap: 8px;
  font-size: 12px;
}

.dl dt {
  color: var(--q-muted-foreground);
  font-weight: 500;
}

.dl dd {
  margin: 0;
}

.danger {
  appearance: none;
  margin-top: 16px;
  height: 30px;
  padding: 0 12px;
  border: 1px solid color-mix(in srgb, var(--q-destructive) 50%, transparent);
  border-radius: var(--q-radius-control);
  background: transparent;
  color: var(--q-destructive);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}

.danger:hover {
  background: color-mix(in srgb, var(--q-destructive) 12%, transparent);
}
</style>
