import { defineStore } from "pinia";
import { computed, ref } from "vue";

/** Flutter MainScreen workspace selection — chrome routing, not DB. */
export type WorkspaceSurface = "empty" | "connectionHome" | "tableObject";

export type HomeStripTab = "overview" | "sql";
export type ObjectStripTab = "data" | "relations";

export type SelectedObject = {
  connectionId: string;
  name: string;
  kind: "table" | "view";
  /** Stable object id when known (`sqlite:table:main:users`). */
  objectId?: string;
  schema?: string | null;
};

export const useShellNavStore = defineStore("shellNav", () => {
  const selectedConnectionId = ref<string | null>(null);
  const selectedObject = ref<SelectedObject | null>(null);
  const homeTab = ref<HomeStripTab>("overview");
  const objectTab = ref<ObjectStripTab>("data");
  /** Expanded connection ids in the SERVERS tree (Flutter expand = show objects). */
  const expandedConnectionIds = ref<string[]>([]);

  const surface = computed<WorkspaceSurface>(() => {
    if (selectedObject.value) return "tableObject";
    if (selectedConnectionId.value) return "connectionHome";
    return "empty";
  });

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
    const set = new Set(expandedConnectionIds.value);
    if (set.has(id)) set.delete(id);
    else set.add(id);
    expandedConnectionIds.value = [...set];
  }

  function setExpanded(id: string, expanded: boolean) {
    const set = new Set(expandedConnectionIds.value);
    if (expanded) set.add(id);
    else set.delete(id);
    expandedConnectionIds.value = [...set];
  }

  function reset() {
    selectedConnectionId.value = null;
    selectedObject.value = null;
    homeTab.value = "overview";
    objectTab.value = "data";
    expandedConnectionIds.value = [];
  }

  return {
    selectedConnectionId,
    selectedObject,
    homeTab,
    objectTab,
    expandedConnectionIds,
    surface,
    selectConnection,
    selectObject,
    clearObject,
    toggleExpanded,
    setExpanded,
    reset,
  };
});
