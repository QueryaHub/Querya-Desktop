import { describe, expect, it } from "vitest";
import type { ErdSchema } from "../../api/connection";
import { schemaToFlow } from "./layout";

const fixture: ErdSchema = {
  tables: [
    {
      name: "users",
      columns: [
        {
          name: "id",
          dataType: "INTEGER",
          isPrimaryKey: true,
          isForeignKey: false,
          isNullable: false,
        },
      ],
    },
    {
      name: "orders",
      columns: [
        {
          name: "id",
          dataType: "INTEGER",
          isPrimaryKey: true,
          isForeignKey: false,
          isNullable: false,
        },
        {
          name: "user_id",
          dataType: "INTEGER",
          isPrimaryKey: false,
          isForeignKey: true,
          isNullable: false,
        },
      ],
    },
  ],
  relations: [
    {
      fromTable: "orders",
      fromColumn: "user_id",
      toTable: "users",
      toColumn: "id",
    },
  ],
};

describe("schemaToFlow", () => {
  it("maps tables to erdTable nodes and FK edges", () => {
    const { nodes, edges } = schemaToFlow(fixture);
    expect(nodes).toHaveLength(2);
    expect(nodes.every((n) => n.type === "erdTable")).toBe(true);
    expect(nodes.map((n) => n.id).sort()).toEqual(["orders", "users"]);
    expect(edges).toHaveLength(1);
    expect(edges[0].source).toBe("users");
    expect(edges[0].target).toBe("orders");
    expect(Number.isFinite(nodes[0].position.x)).toBe(true);
    expect(Number.isFinite(nodes[0].position.y)).toBe(true);
  });
});
