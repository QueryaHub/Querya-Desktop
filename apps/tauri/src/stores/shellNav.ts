import { defineStore } from "pinia";
import { computed, reactive, ref } from "vue";

/** Flutter MainScreen workspace selection — chrome routing, not DB. */
export type WorkspaceSurface = "empty" | "connectionHome" | "tableObject";

export type HomeStripTab = "overview" | "sql";
export type ObjectStripTab = "data" | "relations";

export type SelectedObject = {
  connectionId: string;
  name: string;
  kind: "table" | "view" | "materialized_view";
  /** Stable object id when known (`sqlite:table:main:users`). */
  objectId?: string;
  schema?: string | null;
};

export const useShellNavStore = defineStore("shellNav", () => {
  const selectedConnectionId = ref<string | null>(null);
  const selectedObject = ref<SelectedObject | null>(null);
  const homeTab = ref<HomeStripTab>("overview");
  const objectTab = ref<ObjectStripTab>("data");
  /** Expanded SERVERS rows — Record avoids Set→array realloc on every toggle. */
  const expanded = reactive<Record<string, true>>({});

  const surface = computed<WorkspaceSurface>(() => {
    if (selectedObject.value) return "tableObject";
    if (selectedConnectionId.value) return "connectionHome";
    return "empty";
  });

  /** Snapshot of expanded ids for watchers (stable when membership unchanged). */
  const expandedConnectionIds = computed(() => Object.keys(expanded));

  function isExpanded(id: string): boolean {
    return expanded[id] === true;
  }

  function selectConnection(id: string | null) {
    selectedConnectionId.value = id;
    selectedObject.value = null;
    homeTab.value = "overview";
  }

  function selectObject(obj: SelectedObject) {
    selectedConnectionId.value = obj.connectionId;
    selectedObject.value = obj;
    objectTab.value = "data";
  }

  function clearObject() {
    selectedObject.value = null;
    homeTab.value = "overview";
  }

  function toggleExpanded(id: string) {
    if (expanded[id]) delete expanded[id];
    else expanded[id] = true;
  }

  function setExpanded(id: string, on: boolean) {
    if (on) expanded[id] = true;
    else delete expanded[id];
  }

  function reset() {
    selectedConnectionId.value = null;
    selectedObject.value = null;
    homeTab.value = "overview";
    objectTab.value = "data";
    for (const k of Object.keys(expanded)) delete expanded[k];
  }

  return {
    selectedConnectionId,
    selectedObject,
    homeTab,
    objectTab,
    expanded,
    expandedConnectionIds,
    isExpanded,
    surface,
    selectConnection,
    selectObject,
    clearObject,
    toggleExpanded,
    setExpanded,
    reset,
  };
});
