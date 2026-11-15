import { defineStore } from "pinia";
import { ref, watch } from "vue";
import {
  dbListColumns,
  dbListTables,
  formatConnectionError,
  type ColumnMeta,
  type SchemaObject,
} from "../api/connection";
import { useConnectionsStore } from "./connections";
import { useShellStatusStore } from "./shellStatus";

export type TreeTableNode = SchemaObject & {
  expanded: boolean;
  loadingColumns: boolean;
  columns: ColumnMeta[] | null;
  error: string | null;
};

/** SQLite object tree for the active connection. */
export const useObjectTreeStore = defineStore("objectTree", () => {
  const connectionId = ref<string | null>(null);
  const objects = ref<TreeTableNode[]>([]);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const filter = ref("");

  async function loadFor(id: string | null) {
    connectionId.value = id;
    objects.value = [];
    error.value = null;
    filter.value = "";
    if (!id) return;

    loading.value = true;
    try {
      const list = await dbListTables(id);
      objects.value = list.map((o) => ({
        ...o,
        expanded: false,
        loadingColumns: false,
        columns: null,
        error: null,
      }));
    } catch (err) {
      error.value = formatConnectionError(err);
    } finally {
      loading.value = false;
    }
  }

  async function toggleTable(name: string) {
    const id = connectionId.value;
    const node = objects.value.find((o) => o.name === name);
    if (!id || !node) return;

    if (node.expanded) {
      node.expanded = false;
      return;
    }

    node.expanded = true;
    if (node.columns) return;

    node.loadingColumns = true;
    node.error = null;
    try {
      const schema = await dbListColumns(id, name);
      node.columns = schema.columns;
    } catch (err) {
      node.error = formatConnectionError(err);
      const status = useShellStatusStore();
      status.setQueryMetrics({
        message: node.error,
        busy: false,
      });
    } finally {
      node.loadingColumns = false;
    }
  }

  function refresh() {
    return loadFor(connectionId.value);
  }

  // Keep tree in sync with active connection.
  const connections = useConnectionsStore();
  watch(
    () => connections.activeId,
    (id) => {
      void loadFor(id);
    },
    { immediate: true },
  );

  return {
    connectionId,
    objects,
    loading,
    error,
    filter,
    loadFor,
    toggleTable,
    refresh,
  };
});
