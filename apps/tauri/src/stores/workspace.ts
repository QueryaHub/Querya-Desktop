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

/** Demo workspace tabs — SQL/result content lands in later issues. */
export const useWorkspaceStore = defineStore("workspace", () => {
  const tabs = ref<WorkspaceTab[]>([
    { id: "tab-1", title: "Welcome", kind: "welcome" },
  ]);
  const activeId = ref("tab-1");

  const activeTab = computed(
    () => tabs.value.find((t) => t.id === activeId.value) ?? null,
  );

  function activate(id: string) {
    if (tabs.value.some((t) => t.id === id)) activeId.value = id;
  }

  function addTab(partial?: Partial<Pick<WorkspaceTab, "title" | "kind">>) {
    const tab: WorkspaceTab = {
      id: nextId(),
      title: partial?.title ?? `Query ${seq}`,
      kind: partial?.kind ?? "sql",
    };
    tabs.value = [...tabs.value, tab];
    activeId.value = tab.id;
    return tab;
  }

  function closeTab(id: string) {
    const idx = tabs.value.findIndex((t) => t.id === id);
    if (idx < 0) return;
    if (tabs.value.length === 1) {
      // Keep at least a welcome tab.
      tabs.value = [{ id: nextId(), title: "Welcome", kind: "welcome" }];
      activeId.value = tabs.value[0].id;
      return;
    }
    const next = tabs.value.filter((t) => t.id !== id);
    tabs.value = next;
    if (activeId.value === id) {
      const fallback = next[Math.max(0, idx - 1)] ?? next[0];
      activeId.value = fallback.id;
    }
  }

  return { tabs, activeId, activeTab, activate, addTab, closeTab };
});
