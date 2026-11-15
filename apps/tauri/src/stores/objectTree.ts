import { defineStore } from "pinia";
import { computed, ref, watch } from "vue";
import {
  dbListChildren,
  formatConnectionError,
  type SqlObjectNode,
} from "../api/connection";
import { demoListChildren } from "../mock/demoCatalog";
import { useConnectionsStore } from "./connections";
import { useShellNavStore } from "./shellNav";

export type TreeUiNode = SqlObjectNode & {
  expanded: boolean;
  loading: boolean;
  children: TreeUiNode[] | null;
  error: string | null;
};

function toUi(nodes: SqlObjectNode[]): TreeUiNode[] {
  return nodes.map((n) => ({
    ...n,
    expanded: false,
    loading: false,
    children: n.expandable ? null : [],
    error: null,
  }));
}

function findNode(nodes: TreeUiNode[], id: string): TreeUiNode | null {
  for (const n of nodes) {
    if (n.id === id) return n;
    if (n.children) {
      const hit = findNode(n.children, id);
      if (hit) return hit;
    }
  }
  return null;
}

/** Keep nodes that match `q` or have a matching descendant. */
export function filterTree(nodes: TreeUiNode[], q: string): TreeUiNode[] {
  if (!q) return nodes;
  const out: TreeUiNode[] = [];
  for (const n of nodes) {
    const nameHit = n.name.toLowerCase().includes(q);
    const kids = n.children ? filterTree(n.children, q) : null;
    const kidHit = (kids?.length ?? 0) > 0;
    if (nameHit || kidHit) {
      out.push({
        ...n,
        expanded: nameHit || kidHit || n.expanded,
        children: kids ?? n.children,
      });
    }
  }
  return out;
}

export const useObjectTreeStore = defineStore("objectTree", () => {
  const connectionId = ref<string | null>(null);
  const roots = ref<TreeUiNode[]>([]);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const filter = ref("");

  function isMock(id: string): boolean {
    return Boolean(useConnectionsStore().byId.get(id)?.mock);
  }

  async function fetchChildren(
    connId: string,
    parentId: string | null,
  ): Promise<SqlObjectNode[]> {
    if (isMock(connId)) return demoListChildren(parentId);
    return dbListChildren(connId, parentId);
  }

  async function loadFor(id: string | null) {
    connectionId.value = id;
    roots.value = [];
    error.value = null;
    filter.value = "";
    if (!id) return;

    loading.value = true;
    try {
      roots.value = toUi(await fetchChildren(id, null));
      // SQLite / Demo: single `main` schema — expand so tables show immediately.
      const [only] = roots.value;
      if (roots.value.length === 1 && only?.expandable) {
        await expandNode(id, only);
      }
    } catch (err) {
      error.value = formatConnectionError(err);
    } finally {
      loading.value = false;
    }
  }

  async function expandNode(connId: string, node: TreeUiNode) {
    node.expanded = true;
    if (node.children) return;
    node.loading = true;
    node.error = null;
    try {
      node.children = toUi(await fetchChildren(connId, node.id));
    } catch (err) {
      node.error = formatConnectionError(err);
      node.children = [];
    } finally {
      node.loading = false;
    }
  }

  async function toggleExpand(nodeId: string) {
    const id = connectionId.value;
    const node = findNode(roots.value, nodeId);
    if (!id || !node || !node.expandable) return;

    if (node.expanded) {
      node.expanded = false;
      return;
    }
    await expandNode(id, node);
  }

  /** Flat tables/views under loaded schema children (for ConnectionHome quick list). */
  const relations = computed(() => {
    const out: TreeUiNode[] = [];
    for (const root of roots.value) {
      for (const child of root.children ?? []) {
        if (child.kind === "table" || child.kind === "view") out.push(child);
      }
    }
    return out;
  });

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
    roots,
    relations,
    loading,
    error,
    filter,
    loadFor,
    toggleExpand,
    refresh,
  };
});
