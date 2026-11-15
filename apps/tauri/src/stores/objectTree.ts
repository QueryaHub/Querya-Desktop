import { defineStore } from "pinia";
import { computed, reactive, watch } from "vue";
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

type ConnTreeState = {
  roots: TreeUiNode[];
  loading: boolean;
  error: string | null;
  filter: string;
  loaded: boolean;
};

function emptyState(): ConnTreeState {
  return {
    roots: [],
    loading: false,
    error: null,
    filter: "",
    loaded: false,
  };
}

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

function relationsOf(roots: TreeUiNode[]): TreeUiNode[] {
  const out: TreeUiNode[] = [];
  for (const root of roots) {
    for (const child of root.children ?? []) {
      if (child.kind === "table" || child.kind === "view") out.push(child);
    }
  }
  return out;
}

/**
 * Per-connection object tree cache so multiple SERVERS rows can stay expanded
 * (Flutter `_expandedConnections` behavior).
 */
export const useObjectTreeStore = defineStore("objectTree", () => {
  const byConnection = reactive<Record<string, ConnTreeState>>({});

  function stateOf(connId: string): ConnTreeState {
    if (!byConnection[connId]) byConnection[connId] = emptyState();
    return byConnection[connId]!;
  }

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

  async function ensureLoaded(connId: string, force = false) {
    const st = stateOf(connId);
    if (st.loaded && !force) return;
    st.loading = true;
    st.error = null;
    try {
      await useConnectionsStore().ensureConnected(connId);
      st.roots = toUi(await fetchChildren(connId, null));
      const [only] = st.roots;
      if (st.roots.length === 1 && only?.expandable) {
        await expandNode(connId, only);
      }
      st.loaded = true;
    } catch (err) {
      st.error = formatConnectionError(err);
      st.roots = [];
      st.loaded = false;
    } finally {
      st.loading = false;
    }
  }

  async function loadFor(id: string | null, force = false) {
    if (!id) return;
    await ensureLoaded(id, force);
  }

  async function toggleExpand(connId: string, nodeId: string) {
    const st = stateOf(connId);
    const node = findNode(st.roots, nodeId);
    if (!node || !node.expandable) return;
    if (node.expanded) {
      node.expanded = false;
      return;
    }
    await expandNode(connId, node);
  }

  function setFilter(connId: string, value: string) {
    stateOf(connId).filter = value;
  }

  function drop(connId: string) {
    delete byConnection[connId];
  }

  function refresh(connId: string) {
    return ensureLoaded(connId, true);
  }

  const nav = useShellNavStore();

  /** Selected connection — for ConnectionHome / QuickSwitcher. */
  const connectionId = computed(() => nav.selectedConnectionId);
  const roots = computed(() => {
    const id = nav.selectedConnectionId;
    return id ? stateOf(id).roots : [];
  });
  const loading = computed(() => {
    const id = nav.selectedConnectionId;
    return id ? stateOf(id).loading : false;
  });
  const error = computed(() => {
    const id = nav.selectedConnectionId;
    return id ? stateOf(id).error : null;
  });
  const filter = computed({
    get: () => {
      const id = nav.selectedConnectionId;
      return id ? stateOf(id).filter : "";
    },
    set: (v: string) => {
      const id = nav.selectedConnectionId;
      if (id) setFilter(id, v);
    },
  });
  const relations = computed(() => relationsOf(roots.value));

  watch(
    () => nav.selectedConnectionId,
    (id) => {
      if (id) void ensureLoaded(id);
    },
    { immediate: true },
  );

  watch(
    () => nav.expandedConnectionIds,
    (ids) => {
      for (const id of ids) void ensureLoaded(id);
    },
    { immediate: true },
  );

  /** Memoized filter per connection — avoids recloning the tree every panel paint. */
  const filteredRootsByConnection = computed(() => {
    const out: Record<string, TreeUiNode[]> = {};
    for (const id of Object.keys(byConnection)) {
      const st = byConnection[id]!;
      const q = st.filter.trim().toLowerCase();
      out[id] = q ? filterTree(st.roots, q) : st.roots;
    }
    return out;
  });

  function filteredRootsFor(connId: string): TreeUiNode[] {
    return filteredRootsByConnection.value[connId] ?? stateOf(connId).roots;
  }

  return {
    byConnection,
    connectionId,
    roots,
    relations,
    loading,
    error,
    filter,
    filteredRootsByConnection,
    filteredRootsFor,
    stateOf,
    ensureLoaded,
    loadFor,
    toggleExpand,
    setFilter,
    drop,
    refresh,
    relationsOf,
  };
});
