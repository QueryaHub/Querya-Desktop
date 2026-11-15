/** Offline demo catalog for UI-core review (no live DB). */

export type DemoColumn = {
  name: string;
  data_type: string;
  is_primary_key: boolean;
  is_nullable: boolean;
};

export type DemoObject = {
  name: string;
  kind: "table" | "view";
  columns: DemoColumn[];
  rows: unknown[][];
};

export type DemoConnection = {
  id: string;
  name: string;
  driver: "sqlite";
  path: string;
  objects: DemoObject[];
};

const users: DemoObject = {
  name: "users",
  kind: "table",
  columns: [
    { name: "id", data_type: "INTEGER", is_primary_key: true, is_nullable: false },
    { name: "username", data_type: "TEXT", is_primary_key: false, is_nullable: false },
    { name: "email", data_type: "TEXT", is_primary_key: false, is_nullable: false },
    { name: "full_name", data_type: "TEXT", is_primary_key: false, is_nullable: true },
    { name: "city", data_type: "TEXT", is_primary_key: false, is_nullable: true },
    { name: "is_active", data_type: "INTEGER", is_primary_key: false, is_nullable: false },
    { name: "created_at", data_type: "DATETIME", is_primary_key: false, is_nullable: false },
  ],
  rows: [
    [1, "ada", "ada@ex.com", "Ada Lovelace", "London", 1, "2024-01-02 10:00:00"],
    [2, "bob", "bob@ex.com", "Bob Builder", "Berlin", 1, "2024-02-11 12:30:00"],
    [3, "cara", "cara@ex.com", null, "Oslo", 0, "2024-03-05 09:15:00"],
    [4, "dan", "dan@ex.com", "Dan Park", "Tokyo", 1, "2024-04-18 18:45:00"],
    [5, "eve", "eve@ex.com", "Eve North", "Seoul", 1, "2024-05-01 08:00:00"],
  ],
};

const products: DemoObject = {
  name: "products",
  kind: "table",
  columns: [
    { name: "id", data_type: "INTEGER", is_primary_key: true, is_nullable: false },
    { name: "sku", data_type: "TEXT", is_primary_key: false, is_nullable: false },
    { name: "title", data_type: "TEXT", is_primary_key: false, is_nullable: false },
    { name: "price", data_type: "REAL", is_primary_key: false, is_nullable: false },
  ],
  rows: [
    [10, "SKU-1", "Notebook", 12.5],
    [11, "SKU-2", "Pen set", 4.2],
    [12, "SKU-3", "Desk lamp", 39.0],
  ],
};

const orders: DemoObject = {
  name: "orders",
  kind: "table",
  columns: [
    { name: "id", data_type: "INTEGER", is_primary_key: true, is_nullable: false },
    { name: "user_id", data_type: "INTEGER", is_primary_key: false, is_nullable: false },
    { name: "total", data_type: "REAL", is_primary_key: false, is_nullable: false },
    { name: "status", data_type: "TEXT", is_primary_key: false, is_nullable: false },
  ],
  rows: [
    [100, 1, 44.5, "paid"],
    [101, 2, 12.5, "pending"],
    [102, 1, 39.0, "paid"],
  ],
};

const customerSpending: DemoObject = {
  name: "customer_spending",
  kind: "view",
  columns: [
    { name: "username", data_type: "TEXT", is_primary_key: false, is_nullable: false },
    { name: "spent", data_type: "REAL", is_primary_key: false, is_nullable: false },
  ],
  rows: [
    ["ada", 83.5],
    ["bob", 12.5],
  ],
};

export const DEMO_CONNECTION: DemoConnection = {
  id: "demo-sqlite",
  name: "Demo SQLite",
  driver: "sqlite",
  path: "mock://demo",
  objects: [users, products, orders, customerSpending],
};

export function findDemoObject(name: string): DemoObject | undefined {
  return DEMO_CONNECTION.objects.find((o) => o.name === name);
}
