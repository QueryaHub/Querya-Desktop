import { defineStore } from "pinia";
import { computed, ref } from "vue";

export type WorkspaceTabKind = "welcome" | "sql" | "result";

export type WorkspaceTab = {
  id: string;
  title: string;
  kind: WorkspaceTabKind;
};

let seq = 1;

function nextId(): string {
  seq += 1;
  return `tab-${seq}`;
}

const DEFAULT_SQL = "SELECT name FROM sqlite_master WHERE type = 'table';\n";

/** Workspace tabs + per-tab SQL buffers. */
export const useWorkspaceStore = defineStore("workspace", () => {
  const tabs = ref<WorkspaceTab[]>([
    { id: "tab-1", title: "Welcome", kind: "welcome" },
  ]);
  const activeId = ref("tab-1");
  const sqlBuffers = ref<Record<string, string>>({});

  const activeTab = computed(
    () => tabs.value.find((t) => t.id === activeId.value) ?? null,
  );

  function activate(id: string) {
    if (tabs.value.some((t) => t.id === id)) activeId.value = id;
  }

  function ensureSql(id: string, seed = DEFAULT_SQL) {
    if (!(id in sqlBuffers.value)) {
      sqlBuffers.value[id] = seed;
    }
  }

  function sqlFor(id: string): string {
    return sqlBuffers.value[id] ?? DEFAULT_SQL;
  }

  function setSql(id: string, sql: string) {
    // In-place — avoid `{ ...buffers }` identity churn on every keystroke.
    sqlBuffers.value[id] = sql;
  }

  function addTab(partial?: Partial<Pick<WorkspaceTab, "title" | "kind">>) {
    const tab: WorkspaceTab = {
      id: nextId(),
      title: partial?.title ?? `Query ${seq}`,
      kind: partial?.kind ?? "sql",
    };
    tabs.value = [...tabs.value, tab];
    if (tab.kind === "sql") ensureSql(tab.id);
    activeId.value = tab.id;
    return tab;
  }

  function closeTab(id: string) {
    const idx = tabs.value.findIndex((t) => t.id === id);
    if (idx < 0) return;
    delete sqlBuffers.value[id];
    if (tabs.value.length === 1) {
      const welcome = { id: nextId(), title: "Welcome", kind: "welcome" as const };
      tabs.value = [welcome];
      activeId.value = welcome.id;
      return;
    }
    const next = tabs.value.filter((t) => t.id !== id);
    tabs.value = next;
    if (activeId.value === id) {
      const fallback = next[Math.max(0, idx - 1)] ?? next[0];
      activeId.value = fallback.id;
    }
  }

  return {
    tabs,
    activeId,
    activeTab,
    sqlBuffers,
    activate,
    addTab,
    closeTab,
    ensureSql,
    sqlFor,
    setSql,
  };
});
