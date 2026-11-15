import dagre from "@dagrejs/dagre";
import type { Edge, Node } from "@vue-flow/core";
import type { ErdSchema, ErdTable } from "../../api/connection";

export type ErdTableNodeData = {
  table: ErdTable;
};

const NODE_WIDTH = 260;
const COL_ROW_H = 22;
const HEADER_H = 36;

export function estimateTableHeight(table: ErdTable): number {
  return HEADER_H + Math.max(1, table.columns.length) * COL_ROW_H + 8;
}

/** Map catalog → Vue Flow nodes/edges with dagre layout (LR). */
export function schemaToFlow(schema: ErdSchema): {
  nodes: Node<ErdTableNodeData>[];
  edges: Edge[];
} {
  const g = new dagre.graphlib.Graph();
  g.setDefaultEdgeLabel(() => ({}));
  g.setGraph({ rankdir: "LR", nodesep: 40, ranksep: 80, marginx: 24, marginy: 24 });

  for (const table of schema.tables) {
    g.setNode(table.name, {
      width: NODE_WIDTH,
      height: estimateTableHeight(table),
    });
  }
  for (const rel of schema.relations) {
    if (!g.hasNode(rel.fromTable) || !g.hasNode(rel.toTable)) continue;
    // Edge direction: referenced ← referencing for left-to-right parents→children feel.
    g.setEdge(rel.toTable, rel.fromTable);
  }
  dagre.layout(g);

  const nodes: Node<ErdTableNodeData>[] = schema.tables.map((table) => {
    const pos = g.node(table.name);
    const h = estimateTableHeight(table);
    return {
      id: table.name,
      type: "erdTable",
      position: {
        x: (pos?.x ?? 0) - NODE_WIDTH / 2,
        y: (pos?.y ?? 0) - h / 2,
      },
      data: { table },
      draggable: true,
    };
  });

  const edges: Edge[] = schema.relations.map((rel, i) => ({
    id: `fk-${i}-${rel.fromTable}.${rel.fromColumn}->${rel.toTable}.${rel.toColumn}`,
    source: rel.toTable,
    target: rel.fromTable,
    sourceHandle: `out-${rel.toColumn}`,
    targetHandle: `in-${rel.fromColumn}`,
    type: "smoothstep",
    animated: false,
    label: rel.oneToOne ? "1:1" : rel.optional ? "0..*" : "1..*",
    style: { stroke: "var(--q-primary)", strokeWidth: 1.5 },
    labelStyle: { fill: "var(--q-muted-foreground)", fontSize: 10 },
  }));

  return { nodes, edges };
}
