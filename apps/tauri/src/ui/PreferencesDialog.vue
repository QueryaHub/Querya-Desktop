<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import {
  applyTheme,
  readStoredTheme,
  type QueryaThemeMode,
} from "../theme/queryaTheme";
import { useQueryaMotion } from "../motion";
import type { QueryaMotionLevel } from "../motion/types";
import { usePreferencesStore } from "../stores/preferences";
import {
  allShortcuts,
  shortcutCategories,
  type ShortcutItem,
} from "../preferences/shortcutsCatalog";
import InterfaceScaleSlider from "./InterfaceScaleSlider.vue";

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

type CategoryId =
  | "general"
  | "appearance"
  | "sql"
  | "dataGrid"
  | "extensions"
  | "mcp"
  | "shortcuts"
  | "about";

type Category = {
  id: CategoryId;
  label: string;
  description: string;
  /** Display glyph (Flutter rail icon stand-in). */
  icon: string;
  keywords: string;
};

type TimeoutKey = "pgTimeoutSec" | "mysqlTimeoutSec" | "sqliteTimeoutSec";

const categories: Category[] = [
  {
    id: "general",
    label: "General",
    description: "Startup, updates, release channel",
    icon: "⚙",
    keywords: "updates startup automatic release channel stable beta",
  },
  {
    id: "appearance",
    label: "Appearance",
    description: "Themes, dark mode, scaling, animations",
    icon: "◇",
    keywords: "theme dark light system scaling motion animation interface color",
  },
  {
    id: "sql",
    label: "SQL & Editor",
    description: "Editor font, statement timeouts, query history",
    icon: "›_",
    keywords:
      "font size postgresql mysql sqlite statement timeout history destructive drop truncate delete",
  },
  {
    id: "dataGrid",
    label: "Data Grid",
    description: "Result rows limit, column sizing, safety",
    icon: "▦",
    keywords: "max rows results grid column size formatting safety limits",
  },
  {
    id: "extensions",
    label: "Extensions",
    description: "Sideloading .qext/.zip packages, extension folder",
    icon: "⧉",
    keywords: "extensions qext zip package install sideload folder directory",
  },
  {
    id: "mcp",
    label: "MCP Server",
    description: "Let AI clients read shared connections",
    icon: "◉",
    keywords: "mcp ai model claude cursor vscode copilot llm server share token",
  },
  {
    id: "shortcuts",
    label: "Shortcuts",
    description: "Keyboard shortcuts reference and keymap",
    icon: "⌘",
    keywords: "shortcut keyboard keymap hotkey",
  },
  {
    id: "about",
    label: "About & Storage",
    description: "App version, local SQLite storage, paths",
    icon: "ℹ",
    keywords: "about version storage directory cache logs sqlite",
  },
];

const TIMEOUT_OPTS = [
  { value: "", label: "No limit" },
  { value: "10", label: "10 s" },
  { value: "30", label: "30 s" },
  { value: "60", label: "60 s" },
  { value: "120", label: "2 min" },
  { value: "300", label: "5 min" },
  { value: "600", label: "10 min" },
];

const HISTORY_OPTS = [25, 50, 100, 200, 500];
const ROWS_OPTS = [1000, 2500, 5000, 10000, 25000, 50000, 100000];

const category = ref<CategoryId>("general");
const search = ref("");
const searchEl = ref<HTMLInputElement | null>(null);
const shortcutChip = ref<(typeof shortcutCategories)[number]>("All");
const themeMode = ref<QueryaThemeMode>(readStoredTheme());
const prefs = usePreferencesStore();
const motion = useQueryaMotion();
const extMsg = ref<string | null>(null);

const searchQuery = computed(() => search.value.trim().toLowerCase());
const hasSearch = computed(() => searchQuery.value.length > 0);

function shortcutMatches(s: ShortcutItem, q: string): boolean {
  return [s.action, s.description ?? "", s.category, s.keys.join(" ")]
    .join(" ")
    .toLowerCase()
    .includes(q);
}

function matchCountFor(cat: Category, q: string): number {
  if (!q) return 0;
  let n = 0;
  if (cat.label.toLowerCase().includes(q)) n++;
  if (cat.description.toLowerCase().includes(q)) n++;
  // Flutter: keyword bag via String.contains on the whole bag.
  if (cat.keywords.includes(q)) n++;
  if (cat.id === "shortcuts") {
    n += allShortcuts.filter((s) => shortcutMatches(s, q)).length;
  }
  return n;
}

const matchCounts = computed(() => {
  const q = searchQuery.value;
  const counts = {} as Record<CategoryId, number>;
  for (const cat of categories) {
    counts[cat.id] = matchCountFor(cat, q);
  }
  return counts;
});

const shortcutChipCounts = computed(() => {
  const counts: Record<string, number> = { All: allShortcuts.length };
  for (const s of allShortcuts) {
    counts[s.category] = (counts[s.category] ?? 0) + 1;
  }
  return counts;
});

const filteredShortcuts = computed(() => {
  const q = searchQuery.value;
  const chip = shortcutChip.value;
  return allShortcuts.filter((s) => {
    if (chip !== "All" && s.category !== chip) return false;
    return !q || shortcutMatches(s, q);
  });
});

const shortcutGroups = computed(() => {
  const map = new Map<string, ShortcutItem[]>();
  for (const s of filteredShortcuts.value) {
    const list = map.get(s.category) ?? [];
    list.push(s);
    map.set(s.category, list);
  }
  return [...map.entries()];
});

function timeoutModel(key: TimeoutKey) {
  return computed({
    get: () => {
      const v = prefs.state[key];
      return v == null ? "" : String(v);
    },
    set: (v: string) => {
      prefs.state[key] = v === "" ? null : Number(v);
    },
  });
}

const pgTimeout = timeoutModel("pgTimeoutSec");
const mysqlTimeout = timeoutModel("mysqlTimeoutSec");
const sqliteTimeout = timeoutModel("sqliteTimeoutSec");

function onThemeChange(e: Event) {
  const mode = (e.target as HTMLSelectElement).value as QueryaThemeMode;
  themeMode.value = mode;
  applyTheme(mode);
}

function onMotionChange(e: Event) {
  motion.setLevel((e.target as HTMLSelectElement).value as QueryaMotionLevel);
}

function onSearchInput() {
  if (!hasSearch.value) return;
  if (matchCounts.value[category.value] > 0) return;
  const first = categories.find((c) => matchCounts.value[c.id] > 0);
  if (first) category.value = first.id;
}

function clearSearch() {
  search.value = "";
  searchEl.value?.focus();
}

function onInstallExtStub() {
  extMsg.value = "Extension install dialog lands with the marketplace epic.";
}

function onOpenExtFolderStub() {
  extMsg.value = "Open extensions folder — path plumbing next.";
}

function onKey(e: KeyboardEvent) {
  if (!props.open) return;
  if (e.key === "Escape") {
    e.preventDefault();
    emit("close");
    return;
  }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "f") {
    e.preventDefault();
    searchEl.value?.focus();
  }
}

watch(
  () => props.open,
  (open) => {
    if (!open) return;
    category.value = "general";
    search.value = "";
    shortcutChip.value = "All";
    themeMode.value = readStoredTheme();
    extMsg.value = null;
  },
);

onMounted(() => window.addEventListener("keydown", onKey, true));
onUnmounted(() => window.removeEventListener("keydown", onKey, true));
</script>

<template>
  <div
    v-if="open"
    class="overlay q-modal-scrim"
    data-testid="preferences-dialog"
    @click.self="emit('close')"
  >
    <div class="dialog" role="dialog" aria-modal="true" aria-label="Preferences">
      <!-- Header: title + search + close (Flutter) -->
      <header class="header">
        <span class="hdr-icon" aria-hidden="true">⚙</span>
        <h1 class="hdr-title">Preferences</h1>
        <div class="search-wrap" :class="{ active: hasSearch }">
          <span class="search-ico" aria-hidden="true">⌕</span>
          <input
            ref="searchEl"
            v-model="search"
            class="search"
            type="search"
            placeholder="Filter preferences… (Ctrl+F)"
            aria-label="Filter preferences"
            @input="onSearchInput"
          />
          <button
            v-if="hasSearch"
            type="button"
            class="search-clear"
            aria-label="Clear filter"
            @click="clearSearch"
          >
            ✕
          </button>
        </div>
        <button
          type="button"
          class="hdr-close"
          aria-label="Close"
          @click="emit('close')"
        >
          ✕
        </button>
      </header>

      <div class="body">
        <!-- Rail: icon + label only -->
        <aside class="rail">
          <button
            v-for="c in categories"
            :key="c.id"
            type="button"
            class="rail-tile"
            :class="{ on: category === c.id }"
            @click="category = c.id"
          >
            <span class="rail-ico" aria-hidden="true">{{ c.icon }}</span>
            <span class="rail-label">{{ c.label }}</span>
            <span
              v-if="hasSearch && matchCounts[c.id] > 0"
              class="badge"
              :class="{ on: category === c.id }"
            >
              {{ matchCounts[c.id] }}
            </span>
          </button>
        </aside>

        <!-- Detail: content owns section title (no pane header) -->
        <section class="pane">
          <!-- General -->
          <div v-if="category === 'general'" class="section">
            <h2 class="sec-title">General Settings</h2>
            <p class="hint">
              Application startup behavior and update release channels.
            </p>
            <label class="switch-row">
              <div class="switch-copy">
                <span class="t">Check for updates automatically on startup</span>
                <span class="s"
                  >Silently checks GitHub Releases when Querya starts to notify
                  you of new features.</span
                >
              </div>
              <input
                v-model="prefs.state.checkUpdatesOnStartup"
                type="checkbox"
                class="switch"
              />
            </label>
            <div class="field-row">
              <span class="field-label">Release channel</span>
              <div class="field-control">
                <select v-model="prefs.state.updateChannel">
                  <option value="stable">Stable (Recommended)</option>
                  <option value="dev">Beta / Early Access</option>
                </select>
                <p class="field-hint">
                  Stable receives thoroughly tested monthly updates. Beta
                  receives early releases with experimental features.
                </p>
              </div>
            </div>
          </div>

          <!-- Appearance -->
          <div v-else-if="category === 'appearance'" class="section">
            <h2 class="sec-title">Appearance</h2>
            <div class="field-row">
              <span class="field-label">Theme mode</span>
              <div class="field-control">
                <select :value="themeMode" @change="onThemeChange">
                  <option value="system">System (match OS)</option>
                  <option value="dark">Dark</option>
                  <option value="light">Light</option>
                </select>
              </div>
            </div>
            <div class="field-row field-row-scale">
              <span class="field-label">Interface scale</span>
              <div class="field-control">
                <InterfaceScaleSlider v-model="prefs.state.uiScale" />
              </div>
            </div>
            <label class="switch-row">
              <div class="switch-copy">
                <span class="t">Animate theme changes</span>
                <span class="s"
                  >Smooth transitions when switching dark/light. Requires Motion
                  Full or Reduced.</span
                >
              </div>
              <input
                v-model="prefs.state.animateThemeChanges"
                type="checkbox"
                class="switch"
              />
            </label>
            <div class="field-row">
              <span class="field-label">Motion</span>
              <div class="field-control">
                <select :value="motion.level.value" @change="onMotionChange">
                  <option value="full">Full</option>
                  <option value="reduced">Reduced</option>
                  <option value="off">Off</option>
                </select>
                <p class="field-hint">
                  Full enables all animations. Reduced cuts durations in half. Off
                  disables all transitions.
                </p>
              </div>
            </div>
            <div class="card">
              <p class="card-title">Theme Studio</p>
              <p class="card-body">
                Fine-tune workbench and syntax highlight colors with live preview.
              </p>
              <button type="button" class="btn" disabled>
                Edit theme colors…
              </button>
            </div>
            <div class="card">
              <p class="card-title">Theme Actions</p>
              <div class="btn-row">
                <button type="button" class="btn" disabled>Import theme…</button>
                <button type="button" class="btn" disabled>
                  Install from URL…
                </button>
                <button type="button" class="btn" disabled>Refresh themes</button>
                <button type="button" class="btn" disabled>
                  Open themes folder
                </button>
                <button
                  type="button"
                  class="btn"
                  @click="prefs.resetAppearance()"
                >
                  Reset appearance
                </button>
              </div>
              <p class="field-hint">
                Theme packs use VS Code JSON. Remote install requires HTTPS and an
                optional SHA-256 checksum.
              </p>
            </div>
          </div>

          <!-- SQL -->
          <div v-else-if="category === 'sql'" class="section">
            <h2 class="sec-title">SQL &amp; Query Execution</h2>
            <p class="hint">
              Global statement timeouts, editor formatting, and query history.
            </p>
            <div class="field-row">
              <span class="field-label">Editor font size</span>
              <div class="field-control">
                <select v-model.number="prefs.state.editorFontSize">
                  <option :value="11">11 pt</option>
                  <option :value="12">12 pt</option>
                  <option :value="13">13 pt (Default)</option>
                  <option :value="14">14 pt</option>
                  <option :value="16">16 pt</option>
                  <option :value="18">18 pt</option>
                </select>
              </div>
            </div>
            <div class="field-row">
              <span class="field-label">PostgreSQL timeout</span>
              <div class="field-control">
                <select v-model="pgTimeout">
                  <option
                    v-for="o in TIMEOUT_OPTS"
                    :key="o.label"
                    :value="o.value"
                  >
                    {{ o.label }}
                  </option>
                </select>
                <p class="field-hint">
                  Statement timeout applied to queries on PostgreSQL connections.
                </p>
              </div>
            </div>
            <div class="field-row">
              <span class="field-label">MySQL timeout</span>
              <div class="field-control">
                <select v-model="mysqlTimeout">
                  <option
                    v-for="o in TIMEOUT_OPTS"
                    :key="o.label"
                    :value="o.value"
                  >
                    {{ o.label }}
                  </option>
                </select>
                <p class="field-hint">
                  Max execution time applied to queries on MySQL and MariaDB
                  servers.
                </p>
              </div>
            </div>
            <div class="field-row">
              <span class="field-label">SQLite timeout</span>
              <div class="field-control">
                <select v-model="sqliteTimeout">
                  <option
                    v-for="o in TIMEOUT_OPTS"
                    :key="o.label"
                    :value="o.value"
                  >
                    {{ o.label }}
                  </option>
                </select>
                <p class="field-hint">
                  Application-level statement timeout for queries on SQLite
                  connections.
                </p>
              </div>
            </div>
            <div class="field-row">
              <span class="field-label">Query history limit</span>
              <div class="field-control">
                <select v-model.number="prefs.state.historyMax">
                  <option v-for="n in HISTORY_OPTS" :key="n" :value="n">
                    {{ n }} entries
                  </option>
                </select>
                <p class="field-hint">
                  Per connection and database. Older entries are pruned first.
                </p>
              </div>
            </div>
            <label class="switch-row">
              <div class="switch-copy">
                <span class="t">Confirm destructive SQL queries</span>
                <span class="s"
                  >Displays confirmation modal before running DROP, TRUNCATE, or
                  unconditional DELETE queries.</span
                >
              </div>
              <input
                v-model="prefs.state.confirmDestructive"
                type="checkbox"
                class="switch"
              />
            </label>
          </div>

          <!-- Data Grid -->
          <div v-else-if="category === 'dataGrid'" class="section">
            <h2 class="sec-title">Data Grid &amp; Results</h2>
            <p class="hint">How many rows a query result loads into the grid.</p>
            <div class="field-row">
              <span class="field-label">Max rows in results</span>
              <div class="field-control">
                <select v-model.number="prefs.state.maxResultRows">
                  <option v-for="n in ROWS_OPTS" :key="n" :value="n">
                    {{ n }} rows
                  </option>
                </select>
                <p class="field-hint">
                  Limits row count rendered in the virtualized grid to prevent
                  out-of-memory errors on large queries.
                </p>
              </div>
            </div>
          </div>

          <!-- Extensions -->
          <div v-else-if="category === 'extensions'" class="section">
            <h2 class="sec-title">Extensions</h2>
            <p class="hint">
              Install a local .zip or .qext package without the Marketplace.
              Useful for development and offline environments.
            </p>
            <div class="btn-row">
              <button type="button" class="btn" @click="onInstallExtStub">
                Install from file…
              </button>
              <button type="button" class="btn" @click="onOpenExtFolderStub">
                Open extensions folder
              </button>
            </div>
            <p v-if="extMsg" class="msg">{{ extMsg }}</p>
          </div>

          <!-- MCP -->
          <div v-else-if="category === 'mcp'" class="section">
            <h2 class="sec-title">MCP Server</h2>
            <p class="hint">
              Let AI clients (Claude, Cursor, VS Code, Gemini…) read shared
              connections. Credentials are never sent to the model.
            </p>
            <label class="switch-row">
              <div class="switch-copy">
                <span class="t">Enable MCP server</span>
                <span class="s">{{
                  prefs.state.mcpEnabled
                    ? "Running · stub host (Rust MCP epic next)"
                    : "Stopped — enable to expose Querya tools to MCP clients"
                }}</span>
              </div>
              <input
                v-model="prefs.state.mcpEnabled"
                type="checkbox"
                class="switch"
              />
            </label>
            <div class="card">
              <p class="card-title">Shared connections</p>
              <p class="card-body">
                No live connections yet. Open Demo or a database, then choose which
                sessions MCP clients may read.
              </p>
            </div>
            <div class="card">
              <p class="card-title">Connect a client</p>
              <p class="card-body">
                Copy client configs and manage the access token when the in-process
                MCP host lands.
              </p>
              <div class="btn-row">
                <button type="button" class="btn" disabled>
                  Copy Claude Desktop config
                </button>
                <button type="button" class="btn" disabled>
                  Copy Cursor config
                </button>
                <button type="button" class="btn" disabled>
                  Copy VS Code config
                </button>
              </div>
            </div>
          </div>

          <!-- Shortcuts -->
          <div v-else-if="category === 'shortcuts'" class="section shortcuts">
            <div class="chips">
              <button
                v-for="chip in shortcutCategories"
                :key="chip"
                type="button"
                class="chip"
                :class="{ on: shortcutChip === chip }"
                @click="shortcutChip = chip"
              >
                {{ chip }} ({{ shortcutChipCounts[chip] }})
              </button>
            </div>
            <p v-if="!shortcutGroups.length" class="hint">
              No shortcuts match "{{ search }}"
            </p>
            <div
              v-for="[group, items] in shortcutGroups"
              :key="group"
              class="sc-group"
            >
              <h3 class="sc-head">{{ group }}</h3>
              <ul class="sc-list">
                <li v-for="s in items" :key="s.action" class="sc-row">
                  <div class="sc-copy">
                    <span class="t">{{ s.action }}</span>
                    <span v-if="s.description" class="s">{{ s.description }}</span>
                  </div>
                  <div class="sc-keys">
                    <span
                      v-for="(combo, ci) in [s.keys, ...(s.altKeys ?? [])]"
                      :key="ci"
                      class="combo"
                    >
                      <template v-if="ci > 0"><span class="or">or</span></template>
                      <kbd v-for="k in combo" :key="k">{{ k }}</kbd>
                    </span>
                  </div>
                </li>
              </ul>
            </div>
          </div>

          <!-- About -->
          <div v-else class="section">
            <div class="about-card">
              <span class="about-mark" aria-hidden="true" />
              <div>
                <h2 class="about-name">Querya Desktop</h2>
                <p class="s">Version 0.1.0 (Desktop Build)</p>
                <p class="s">Fast, native multi-database management studio.</p>
              </div>
            </div>
            <h2 class="sec-title" style="margin-top: 20px">
              Storage &amp; Directories
            </h2>
            <p class="hint">
              Connection profiles and credentials stay on this machine (local
              SQLite / OS keyring).
            </p>
            <div class="btn-row">
              <button type="button" class="btn" disabled>
                Open app data folder
              </button>
              <button type="button" class="btn" disabled>
                Open themes folder
              </button>
              <button type="button" class="btn" disabled>
                Open extensions folder
              </button>
            </div>
            <h2 class="sec-title" style="margin-top: 20px">
              Community &amp; Support
            </h2>
            <div class="btn-row">
              <a
                class="btn link"
                href="https://github.com/QueryaHub/Querya-Desktop"
                target="_blank"
                rel="noreferrer"
                >GitHub repository</a
              >
              <a
                class="btn link"
                href="https://github.com/QueryaHub/Querya-Desktop/issues"
                target="_blank"
                rel="noreferrer"
                >Report an issue</a
              >
            </div>
          </div>
        </section>
      </div>

      <footer class="footer">
        <p class="hint foot-hint">
          Changes apply immediately and persist locally.
        </p>
        <button type="button" class="btn close-btn" @click="emit('close')">
          Close
        </button>
      </footer>
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
  padding: 4vh 5vw;
}

.dialog {
  width: min(760px, 100%);
  min-width: min(480px, 100%);
  height: min(760px, 100%);
  max-height: min(760px, 92vh);
  display: flex;
  flex-direction: column;
  border-radius: 14px;
  overflow: hidden;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  color: var(--q-foreground);
  box-shadow: 0 16px 48px color-mix(in srgb, #000 35%, transparent);
}

.header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 16px 16px 12px 20px;
  border-bottom: 1px solid
    color-mix(in srgb, var(--q-border) 28%, transparent);
  flex: 0 0 auto;
}

.hdr-icon {
  color: var(--q-primary);
  font-size: 16px;
  line-height: 1;
}

.hdr-title {
  margin: 0;
  font-size: 16px;
  font-weight: 650;
  flex: 0 0 auto;
}

.search-wrap {
  flex: 1;
  min-width: 0;
  height: 32px;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 10px;
  margin-left: 20px;
  border-radius: 6px;
  background: color-mix(in srgb, var(--q-muted-foreground) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--q-border) 25%, transparent);
}

.search-wrap.active {
  border-color: color-mix(in srgb, var(--q-primary) 50%, transparent);
}

.search-ico {
  color: var(--q-muted-foreground);
  font-size: 13px;
}

.search-wrap.active .search-ico {
  color: var(--q-primary);
}

.search {
  flex: 1;
  min-width: 0;
  border: 0;
  background: transparent;
  color: var(--q-foreground);
  font: inherit;
  font-size: 12px;
  outline: none;
}

.search-clear,
.hdr-close {
  appearance: none;
  border: 0;
  background: transparent;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  color: var(--q-muted-foreground);
  cursor: pointer;
  flex: 0 0 auto;
}

.search-clear:hover,
.hdr-close:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

.body {
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-columns: 184px 1fr;
}

.rail {
  overflow: auto;
  padding: 10px 8px;
  border-right: 1px solid
    color-mix(in srgb, var(--q-border) 28%, transparent);
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.rail-tile {
  appearance: none;
  border: 0;
  background: transparent;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 10px;
  border-radius: 6px;
  font: inherit;
  cursor: pointer;
  color: var(--q-foreground);
  text-align: left;
}

.rail-tile:hover {
  background: var(--q-accent);
}

.rail-tile.on {
  background: color-mix(in srgb, var(--q-primary) 12%, transparent);
  color: var(--q-primary);
}

.rail-ico {
  width: 16px;
  text-align: center;
  font-size: 12px;
  opacity: 0.9;
  flex: 0 0 auto;
}

.rail-label {
  flex: 1;
  font-size: 12px;
  font-weight: 400;
}

.rail-tile.on .rail-label {
  font-weight: 600;
}

.badge {
  font-size: 10px;
  font-weight: 600;
  line-height: 1;
  padding: 3px 5px;
  border-radius: 10px;
  background: color-mix(in srgb, var(--q-muted-foreground) 50%, transparent);
  color: var(--q-foreground);
}

.badge.on {
  background: var(--q-primary);
  color: var(--q-primary-foreground);
}

.pane {
  overflow: auto;
  padding: 16px 24px;
}

.section {
  max-width: 100%;
}

.sec-title {
  margin: 0 0 6px;
  font-size: 13px;
  font-weight: 650;
}

.hint {
  margin: 0 0 14px;
  font-size: 12px;
  line-height: 1.35;
  color: color-mix(in srgb, var(--q-foreground) 72%, transparent);
}

.switch-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 6px 0;
  border-radius: 6px;
  cursor: pointer;
  margin-bottom: 4px;
}

.switch-copy {
  min-width: 0;
}

.t {
  display: block;
  font-size: 12px;
  font-weight: 500;
}

.s {
  display: block;
  margin-top: 2px;
  font-size: 11px;
  color: var(--q-muted-foreground);
  line-height: 1.35;
}

.switch {
  width: 36px;
  height: 20px;
  flex: 0 0 auto;
  accent-color: var(--q-primary);
}

.field-row {
  display: flex;
  gap: 12px;
  align-items: flex-start;
  margin: 12px 0 16px;
}

.field-row-scale {
  align-items: center;
}

.field-row-scale .field-label {
  padding-top: 0;
}

.field-label {
  width: 152px;
  flex: 0 0 152px;
  font-size: 12px;
  padding-top: 7px;
}

.field-control {
  flex: 1;
  min-width: 0;
}

.field-control select {
  width: 100%;
  height: 32px;
  border: 1px solid var(--q-border);
  border-radius: 6px;
  background: var(--q-sidebar-bg);
  color: var(--q-foreground);
  padding: 0 10px;
  font: inherit;
  font-size: 12px;
}

.field-hint {
  margin: 4px 0 0;
  font-size: 11px;
  line-height: 1.35;
  color: var(--q-muted-foreground);
}

.card {
  margin: 12px 0;
  padding: 14px;
  border-radius: 8px;
  border: 1px solid color-mix(in srgb, var(--q-border) 70%, transparent);
  background: color-mix(in srgb, var(--q-muted-foreground) 6%, transparent);
}

.card-title {
  margin: 0 0 4px;
  font-size: 12px;
  font-weight: 650;
}

.card-body {
  margin: 0 0 10px;
  font-size: 11px;
  color: var(--q-muted-foreground);
  line-height: 1.4;
}

.btn-row {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
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
  text-decoration: none;
  display: inline-flex;
  align-items: center;
}

.btn:hover:not(:disabled) {
  background: var(--q-accent);
}

.btn:disabled {
  opacity: 0.45;
  cursor: default;
}

.btn.link {
  color: var(--q-primary);
}

.msg {
  margin: 10px 0 0;
  font-size: 12px;
  color: var(--q-muted-foreground);
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 14px;
}

.chip {
  appearance: none;
  border: 1px solid var(--q-border);
  background: transparent;
  color: var(--q-muted-foreground);
  border-radius: 999px;
  padding: 4px 10px;
  font: inherit;
  font-size: 11px;
  cursor: pointer;
}

.chip.on {
  background: color-mix(in srgb, var(--q-primary) 16%, transparent);
  border-color: transparent;
  color: var(--q-primary);
  font-weight: 600;
}

.sc-group {
  margin-bottom: 16px;
}

.sc-head {
  margin: 0 0 6px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--q-muted-foreground);
}

.sc-list {
  list-style: none;
  margin: 0;
  padding: 0;
  border: 1px solid color-mix(in srgb, var(--q-border) 70%, transparent);
  border-radius: 8px;
  overflow: hidden;
}

.sc-row {
  display: flex;
  justify-content: space-between;
  gap: 16px;
  align-items: center;
  padding: 10px 12px;
  border-bottom: 1px solid
    color-mix(in srgb, var(--q-border) 40%, transparent);
}

.sc-row:last-child {
  border-bottom: 0;
}

.sc-keys {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px;
  justify-content: flex-end;
}

.combo {
  display: inline-flex;
  align-items: center;
  gap: 3px;
}

.or {
  margin: 0 4px;
  font-size: 10px;
  color: var(--q-muted-foreground);
}

kbd {
  font-family: var(--q-font-mono);
  font-size: 11px;
  font-weight: 600;
  padding: 2px 6px;
  border-radius: 4px;
  border: 1px solid color-mix(in srgb, var(--q-border) 80%, transparent);
  background: var(--q-sidebar-bg);
}

.about-card {
  display: flex;
  gap: 14px;
  align-items: center;
}

.about-mark {
  width: 48px;
  height: 48px;
  border-radius: 999px;
  background: var(--q-primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--q-primary) 22%, transparent);
  flex: 0 0 auto;
}

.about-name {
  margin: 0 0 4px;
  font-size: 15px;
  font-weight: 650;
}

.footer {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 16px 14px 20px;
  border-top: 1px solid
    color-mix(in srgb, var(--q-border) 28%, transparent);
}

.foot-hint {
  margin: 0;
  flex: 1;
}

.close-btn {
  height: 34px;
  min-width: 88px;
  justify-content: center;
}
</style>
