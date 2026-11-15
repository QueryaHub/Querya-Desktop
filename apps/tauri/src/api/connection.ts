import { invoke } from "@tauri-apps/api/core";

export type SchemaObjectKind = "table" | "view";

export type SchemaObject = {
  name: string;
  kind: SchemaObjectKind;
  schema?: string | null;
};

export type ColumnMeta = {
  name: string;
  data_type: string;
  is_nullable: boolean;
  is_primary_key: boolean;
  primary_key_position?: number | null;
  default_value?: string | null;
};

export type TableSchema = {
  table_name: string;
  schema?: string | null;
  columns: ColumnMeta[];
  primary_keys: string[];
};

export async function dbConnectSqlite(path: string): Promise<string> {
  return invoke<string>("db_connect_sqlite", { path });
}

export async function dbDisconnect(id: string): Promise<void> {
  await invoke("db_disconnect", { id });
}

export async function dbIsConnected(id: string): Promise<boolean> {
  return invoke<boolean>("db_is_connected", { id });
}

export async function dbListSchemas(id: string): Promise<string[]> {
  return invoke<string[]>("db_list_schemas", { id });
}

export async function dbListTables(id: string): Promise<SchemaObject[]> {
  return invoke<SchemaObject[]>("db_list_tables", { id });
}

export async function dbListColumns(
  id: string,
  table: string,
): Promise<TableSchema> {
  return invoke<TableSchema>("db_list_columns", { id, table });
}

export function formatConnectionError(err: unknown): string {
  if (typeof err === "string") return err;
  if (err && typeof err === "object") {
    const e = err as Record<string, unknown>;
    if (typeof e.kind === "string") {
      const parts = [e.kind, e.driver, e.message, e.id].filter(
        (v): v is string => typeof v === "string" && v.length > 0,
      );
      return parts.join(": ");
    }
    if (typeof e.message === "string") return e.message;
  }
  return String(err);
}
