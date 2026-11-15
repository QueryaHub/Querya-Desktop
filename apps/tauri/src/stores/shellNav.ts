import { defineStore } from "pinia";
import { computed, reactive, ref } from "vue";
import type { SqlObjectKind } from "../api/connection";

/** Flutter MainScreen workspace selection — chrome routing, not DB. */
export type WorkspaceSurface =
  | "empty"
  | "connectionHome"
  | "tableObject"
  | "pgObject";

export type HomeStripTab = "overview" | "sql" | "erd";
export type ObjectStripTab = "data" | "relations";

export type RelationKind = "table" | "view" | "materialized_view";

export type PgDetailKind =
  | "function"
  | "sequence"
  | "index"
  | "trigger"
  | "type"
  | "folder";

export type SelectedObject = {
  connectionId: string;
  name: string;
  kind: RelationKind | PgDetailKind;
  /** Stable object id when known (`postgres:function:shop:fn`). */
  objectId?: string;
  schema?: string | null;
};

const RELATION_KINDS = new Set<string>(["table", "view", "materialized_view"]);
const PG_DETAIL_KINDS = new Set<string>([
  "function",
  "sequence",
  "index",
  "trigger",
  "type",
  "folder",
]);
const PG_SCHEMA_TOOL_FOLDERS = new Set(["Indexes", "Triggers", "Types"]);

export function isRelationObjectKind(kind: string): kind is RelationKind {
  return RELATION_KINDS.has(kind);
}

export function isPgDetailObjectKind(kind: string): kind is PgDetailKind {
  return PG_DETAIL_KINDS.has(kind);
}

/** Folders that open a schema listing pane (Flutter schema tool rows). */
export function isPgSchemaToolFolder(node: {
  kind: SqlObjectKind;
  name: string;
}): boolean {
  return node.kind === "folder" && PG_SCHEMA_TOOL_FOLDERS.has(node.name);
}

export const useShellNavStore = defineStore("shellNav", () => {
  const selectedConnectionId = ref<string | null>(null);
  const selectedObject = ref<SelectedObject | null>(null);
  const homeTab = ref<HomeStripTab>("overview");
  const objectTab = ref<ObjectStripTab>("data");
  /** Expanded SERVERS rows — Record avoids Set→array realloc on every toggle. */
  const expanded = reactive<Record<string, true>>({});

  const surface = computed<WorkspaceSurface>(() => {
    const obj = selectedObject.value;
    if (!obj) {
      return selectedConnectionId.value ? "connectionHome" : "empty";
    }
    return isPgDetailObjectKind(obj.kind) ? "pgObject" : "tableObject";
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
