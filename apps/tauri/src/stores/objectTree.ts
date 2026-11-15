import { defineStore } from "pinia";
import { ref, watch } from "vue";
import {
  dbListColumns,
  dbListTables,
  formatConnectionError,
  type ColumnMeta,
  type SchemaObject,
} from "../api/connection";
import { DEMO_CONNECTION } from "../mock/demoCatalog";
import { useConnectionsStore } from "./connections";
import { useShellNavStore } from "./shellNav";

export type TreeTableNode = SchemaObject & {
  expanded: boolean;
  loadingColumns: boolean;
  columns: ColumnMeta[] | null;
  error: string | null;
};

export const useObjectTreeStore = defineStore("objectTree", () => {
  const connectionId = ref<string | null>(null);
  const objects = ref<TreeTableNode[]>([]);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const filter = ref("");

  function fromDemo(): TreeTableNode[] {
    return DEMO_CONNECTION.objects.map((o) => ({
      name: o.name,
      kind: o.kind,
      schema: "main",
      expanded: false,
      loadingColumns: false,
      columns: o.columns.map((c) => ({
        name: c.name,
        data_type: c.data_type,
        is_nullable: c.is_nullable,
        is_primary_key: c.is_primary_key,
      })),
      error: null,
    }));
  }

  async function loadFor(id: string | null) {
    connectionId.value = id;
    objects.value = [];
    error.value = null;
    filter.value = "";
    if (!id) return;

    const connections = useConnectionsStore();
    const conn = connections.byId.get(id);
    if (conn?.mock) {
      objects.value = fromDemo();
      return;
    }

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

  async function toggleColumns(name: string) {
    const id = connectionId.value;
    const node = objects.value.find((o) => o.name === name);
    if (!id || !node) return;

    if (node.expanded) {
      node.expanded = false;
      return;
    }
    node.expanded = true;
    if (node.columns) return;

    const connections = useConnectionsStore();
    if (connections.byId.get(id)?.mock) return;

    node.loadingColumns = true;
    node.error = null;
    try {
      const schema = await dbListColumns(id, name);
      node.columns = schema.columns;
    } catch (err) {
      node.error = formatConnectionError(err);
    } finally {
      node.loadingColumns = false;
    }
  }

  function refresh() {
    return loadFor(connectionId.value);
  }

  const nav = useShellNavStore();
  watch(
    () => nav.selectedConnectionId,
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
    toggleColumns,
    refresh,
  };
});
