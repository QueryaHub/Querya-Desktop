import { invoke } from "@tauri-apps/api/core";

export type SchemaObjectKind = "table" | "view";

export type SchemaObject = {
  name: string;
  kind: SchemaObjectKind;
  schema?: string | null;
};

export type SqlObjectKind =
  | "schema"
  | "folder"
  | "table"
  | "view"
  | "materialized_view"
  | "column"
  | "index"
  | "trigger"
  | "function"
  | "procedure"
  | "sequence"
  | "type";

/** Stable tree node from `db_list_children`. */
export type SqlObjectNode = {
  id: string;
  name: string;
  kind: SqlObjectKind;
  schema?: string | null;
  parent_id?: string | null;
  expandable: boolean;
};

/** Mirrors Rust `ConnectionError` (serde tag = kind). */
export type SqlGuardRule = "empty_query" | "single_statement" | "parse_error";

export type ConnectionError =
  | { kind: "not_found"; id: string }
  | { kind: "already_connected"; id: string }
  | { kind: "disconnected"; id: string }
  | { kind: "invalid_config"; message: string }
  | { kind: "unsupported_driver"; driver: string }
  | { kind: "io"; message: string }
  | { kind: "driver"; driver: string; message: string }
  | { kind: "sql_guard"; rule: SqlGuardRule; message: string };

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

/** Flutter LocalDb connection row (non-secret fields only). */
export type ConnectionProfile = {
  id: string;
  driver: string;
  name: string;
  path?: string | null;
  host?: string | null;
  port?: number | null;
  username?: string | null;
  database_name?: string | null;
  folder_id?: string | null;
  sort_order: number;
  created_at: string;
  updated_at: string;
};

export async function dbConnectSqlite(
  path: string,
  id?: string | null,
): Promise<string> {
  return invoke<string>("db_connect_sqlite", { path, id: id ?? null });
}

export async function dbConnectPostgres(opts: {
  host: string;
  port: number;
  database: string;
  user: string;
  password?: string | null;
  id?: string | null;
}): Promise<string> {
  return invoke<string>("db_connect_postgres", {
    host: opts.host,
    port: opts.port,
    database: opts.database,
    user: opts.user,
    password: opts.password ?? null,
    id: opts.id ?? null,
  });
}

export async function dbConnectMysql(opts: {
  host: string;
  port: number;
  database: string;
  user: string;
  password?: string | null;
  id?: string | null;
}): Promise<string> {
  return invoke<string>("db_connect_mysql", {
    host: opts.host,
    port: opts.port,
    database: opts.database,
    user: opts.user,
    password: opts.password ?? null,
    id: opts.id ?? null,
  });
}

export async function profilesList(): Promise<ConnectionProfile[]> {
  return invoke<ConnectionProfile[]>("profiles_list");
}

export async function profilesUpsert(
  profile: ConnectionProfile,
): Promise<ConnectionProfile> {
  return invoke<ConnectionProfile>("profiles_upsert", { profile });
}

export async function profilesDelete(id: string): Promise<boolean> {
  return invoke<boolean>("profiles_delete", { id });
}

/** Persist SQLite profile + open live session under the same id. */
export async function profilesConnectSqlite(opts: {
  name: string;
  path: string;
  folderId?: string | null;
  id?: string | null;
}): Promise<ConnectionProfile> {
  return invoke<ConnectionProfile>("profiles_connect_sqlite", {
    name: opts.name,
    path: opts.path,
    folderId: opts.folderId ?? null,
    id: opts.id ?? null,
  });
}

/** Persist Postgres metadata (no password on disk) + open live session. */
export async function profilesConnectPostgres(opts: {
  name: string;
  host: string;
  port: number;
  database: string;
  user: string;
  password?: string | null;
  folderId?: string | null;
  id?: string | null;
}): Promise<ConnectionProfile> {
  return invoke<ConnectionProfile>("profiles_connect_postgres", {
    request: {
      name: opts.name,
      host: opts.host,
      port: opts.port,
      database: opts.database,
      user: opts.user,
      password: opts.password ?? null,
      folderId: opts.folderId ?? null,
      id: opts.id ?? null,
    },
  });
}

/** Persist MySQL metadata (no password on disk) + open live session. */
export async function profilesConnectMysql(opts: {
  name: string;
  host: string;
  port: number;
  database: string;
  user: string;
  password?: string | null;
  folderId?: string | null;
  id?: string | null;
}): Promise<ConnectionProfile> {
  return invoke<ConnectionProfile>("profiles_connect_mysql", {
    request: {
      name: opts.name,
      host: opts.host,
      port: opts.port,
      database: opts.database,
      user: opts.user,
      password: opts.password ?? null,
      folderId: opts.folderId ?? null,
      id: opts.id ?? null,
    },
  });
}

export async function dbDisconnect(id: string): Promise<void> {
  await invoke("db_disconnect", { id });
}

export async function dbIsConnected(id: string): Promise<boolean> {
  return invoke<boolean>("db_is_connected", { id });
}

export async function dbListChildren(
  id: string,
  parentId?: string | null,
): Promise<SqlObjectNode[]> {
  return invoke<SqlObjectNode[]>("db_list_children", {
    id,
    parentId: parentId ?? null,
  });
}

export async function dbDescribeObject(
  id: string,
  objectId: string,
): Promise<TableSchema> {
  return invoke<TableSchema>("db_describe_object", { id, objectId });
}

export type FunctionOverload = {
  signature: string;
  definition: string;
};

export type IndexListRow = {
  table_name: string;
  index_name: string;
  definition: string;
  size_bytes: number;
};

export type TriggerListRow = {
  table_name: string;
  trigger_name: string;
  definition: string;
};

export type TypeListRow = {
  name: string;
  type_kind: string;
};

/** Mirrors Rust `PostgresObjectDetail`. */
export type PostgresObjectDetail =
  | {
      kind: "function";
      schema: string;
      name: string;
      overloads: FunctionOverload[];
    }
  | {
      kind: "sequence";
      schema: string;
      name: string;
      last_value: string;
      start_value: string;
      min_value: string;
      max_value: string;
      increment_by: string;
      cache_size: string;
      cycle: boolean;
      ddl: string;
    }
  | {
      kind: "index";
      schema: string;
      table: string;
      name: string;
      definition: string;
      size_bytes: number;
    }
  | {
      kind: "trigger";
      schema: string;
      table: string;
      name: string;
      definition: string;
    }
  | {
      kind: "type";
      schema: string;
      name: string;
      type_kind: string;
    }
  | { kind: "schema_indexes"; schema: string; rows: IndexListRow[] }
  | { kind: "schema_triggers"; schema: string; rows: TriggerListRow[] }
  | { kind: "schema_types"; schema: string; rows: TypeListRow[] };

export async function dbPostgresObjectDetail(
  id: string,
  objectId: string,
): Promise<PostgresObjectDetail> {
  return invoke<PostgresObjectDetail>("db_postgres_object_detail", {
    id,
    objectId,
  });
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

/** Flutter `SqliteConnection.databaseOverview`. */
export type SqliteOverview = {
  version: string;
  page_count: number;
  page_size: number;
  journal_mode: string;
  table_count: number;
  file_size_bytes?: number | null;
};

export async function dbSqliteOverview(id: string): Promise<SqliteOverview> {
  return invoke<SqliteOverview>("db_sqlite_overview", { id });
}

export function isConnectionError(err: unknown): err is ConnectionError {
  return (
    !!err &&
    typeof err === "object" &&
    typeof (err as { kind?: unknown }).kind === "string"
  );
}

export function formatConnectionError(err: unknown): string {
  if (typeof err === "string") return err;
  if (isConnectionError(err)) {
    switch (err.kind) {
      case "sql_guard":
        return `sql_guard: ${err.rule}: ${err.message}`;
      case "driver":
        return `${err.driver}: ${err.message}`;
      case "not_found":
      case "already_connected":
      case "disconnected":
        return `${err.kind}: ${err.id}`;
      case "unsupported_driver":
        return `unsupported_driver: ${err.driver}`;
      case "invalid_config":
      case "io":
        return `${err.kind}: ${err.message}`;
    }
  }
  if (err && typeof err === "object") {
    const e = err as Record<string, unknown>;
    if (typeof e.message === "string") return e.message;
  }
  return String(err);
}
