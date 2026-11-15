/**
 * Semantic Querya icons — Material Symbols Rounded ligatures.
 * Names and glyphs mirror Flutter `lib/core/ui/querya_icons.dart`
 * (`Icons.*_rounded` → Material Symbols Rounded).
 */
export const QUERYA_ICONS = {
  // Chrome
  sidebar: "view_sidebar",
  settings: "settings",
  search: "search",
  info: "info",
  keyboard: "keyboard",
  puzzle: "extension",
  refresh: "refresh",
  chevronRight: "chevron_right",
  chevronDown: "expand_more",
  arrowLeft: "arrow_back",
  house: "home",
  user: "person",
  sparkles: "auto_awesome",
  layout: "dashboard",
  error: "error_outline",

  // Connections / drivers (Material fallbacks; PNGs via QueryaDriverIcon)
  database: "storage",
  server: "dns",
  hardDrive: "storage",
  folder: "folder",
  folderOpen: "folder_open",
  demo: "auto_awesome",
  /** Flutter `connectionIcon('mongodb')` */
  mongo: "eco",
  /** Flutter `connectionIcon('redis')` */
  redis: "memory",
  /** Flutter `connectionIcon('sqlite')` */
  sqlite: "folder_open",

  // Schema tree — Flutter QueryaIcons
  schema: "diamond",
  schemas: "account_tree",
  network: "hub",
  /** Flutter `tableLeaf` */
  table: "grid_on",
  /** Flutter `tableGroup` */
  tableGroup: "table_chart",
  /** Flutter `viewLeaf` */
  view: "view_week",
  /** Flutter `viewGroup` */
  viewGroup: "view_agenda",
  /** Flutter `materializedViewLeaf` */
  materializedView: "layers",
  /** Flutter `functionLeaf` */
  function: "code",
  /** Flutter `functionGroup` */
  functionGroup: "functions",
  /** Flutter `sequenceLeaf` */
  sequence: "looks_one",
  /** Flutter `sequenceGroup` */
  sequenceGroup: "format_list_numbered",
  /** Flutter `indexes` */
  index: "table_rows",
  /** Flutter `triggers` */
  trigger: "bolt",
  /** Flutter `types` */
  type: "category",
  /** Flutter SDUI `columns` */
  column: "view_column",
  extension: "extension",
  binary: "data_object",
  code: "code",
  boxes: "inventory_2",
  grid: "grid_on",
} as const;

export type QueryaIconName = keyof typeof QUERYA_ICONS;

/** Bundled driver PNGs — same files as Flutter `QueryaIcons.connectionAsset`. */
export function connectionAsset(driver: string): string | null {
  switch (driver) {
    case "postgres":
    case "postgresql":
      return "/drivers/postgresql_icon.png";
    case "mysql":
      return "/drivers/mysql_icon.png";
    case "redis":
      return "/drivers/redis_icon.png";
    case "mongodb":
    case "mongo":
      return "/drivers/mongodb_icon.png";
    default:
      return null;
  }
}
