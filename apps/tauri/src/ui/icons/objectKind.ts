import type { SqlObjectKind } from "../../api/connection";
import type { QueryaIconName } from "./registry";

/** Folder display names → Flutter QueryaIcons group glyphs. */
/** Keys must match Rust `SchemaFolderKind::label` / Flutter folder titles. */
const FOLDER_ICONS: Record<string, QueryaIconName> = {
  Tables: "tableGroup",
  Views: "viewGroup",
  "Materialized views": "materializedViewGroup",
  Functions: "functionGroup",
  Sequences: "sequenceGroup",
  Indexes: "index",
  Triggers: "trigger",
  Types: "type",
};

/** Map a tree node to a Querya icon (Flutter `QueryaIcons` parity). */
export function iconForObjectNode(
  kind: SqlObjectKind,
  name?: string,
): QueryaIconName {
  if (kind === "folder") {
    return (name && FOLDER_ICONS[name]) || "folder";
  }
  switch (kind) {
    case "schema":
      return "schema";
    case "table":
      return "table";
    case "view":
      return "view";
    case "materialized_view":
      return "materializedView";
    case "function":
    case "procedure":
      return "function";
    case "sequence":
      return "sequence";
    case "index":
      return "index";
    case "trigger":
      return "trigger";
    case "type":
      return "type";
    case "column":
      return "column";
    default:
      return "table";
  }
}

/** @deprecated Prefer QueryaDriverIcon — kept for tests of Material fallbacks. */
export function iconForDriver(
  driver: string,
  opts?: { mock?: boolean },
): QueryaIconName {
  if (opts?.mock) return "demo";
  switch (driver) {
    case "postgres":
    case "postgresql":
      return "database";
    case "sqlite":
      return "sqlite";
    case "mysql":
      return "tableGroup";
    case "redis":
      return "redis";
    case "mongodb":
      return "mongo";
    default:
      return "extension";
  }
}
