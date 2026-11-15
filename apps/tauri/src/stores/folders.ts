import { defineStore } from "pinia";
import { computed, reactive, watch } from "vue";

const STORAGE_KEY = "querya.folders.v1";

export type ConnectionFolder = {
  id: string;
  name: string;
  /** Expanded in the SERVERS tree. */
  expanded: boolean;
};

type Stored = { folders: { id: string; name: string }[] };

function load(): ConnectionFolder[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as Stored;
    return (parsed.folders ?? []).map((f) => ({
      id: f.id,
      name: f.name,
      expanded: true,
    }));
  } catch {
    return [];
  }
}

function newId(): string {
  return `folder-${crypto.randomUUID()}`;
}

/** In-memory folders for the SERVERS tree (LocalDb persistence later). */
export const useFoldersStore = defineStore("folders", () => {
  const folders = reactive<ConnectionFolder[]>(load());

  watch(
    folders,
    () => {
      const payload: Stored = {
        folders: folders.map(({ id, name }) => ({ id, name })),
      };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    },
    { deep: true },
  );

  const byId = computed(() => {
    const map = new Map<string, ConnectionFolder>();
    for (const f of folders) map.set(f.id, f);
    return map;
  });

  function create(name: string): ConnectionFolder {
    const trimmed = name.trim();
    if (!trimmed) throw new Error("Folder name is empty");
    if (folders.some((f) => f.name.toLowerCase() === trimmed.toLowerCase())) {
      throw new Error(`Folder "${trimmed}" already exists`);
    }
    const folder: ConnectionFolder = {
      id: newId(),
      name: trimmed,
      expanded: true,
    };
    folders.push(folder);
    return folder;
  }

  function remove(id: string) {
    const i = folders.findIndex((f) => f.id === id);
    if (i >= 0) folders.splice(i, 1);
  }

  function rename(id: string, name: string) {
    const f = folders.find((x) => x.id === id);
    if (!f) return;
    const trimmed = name.trim();
    if (!trimmed) return;
    f.name = trimmed;
  }

  function toggleExpanded(id: string) {
    const f = folders.find((x) => x.id === id);
    if (f) f.expanded = !f.expanded;
  }

  function setExpanded(id: string, expanded: boolean) {
    const f = folders.find((x) => x.id === id);
    if (f) f.expanded = expanded;
  }

  /** Seed a sample folder once for Demo UX if none exist. */
  function ensureDemoFolder(): ConnectionFolder {
    const existing = folders.find((f) => f.name === "Samples");
    if (existing) return existing;
    return create("Samples");
  }

  return {
    folders,
    byId,
    create,
    remove,
    rename,
    toggleExpanded,
    setExpanded,
    ensureDemoFolder,
  };
});
