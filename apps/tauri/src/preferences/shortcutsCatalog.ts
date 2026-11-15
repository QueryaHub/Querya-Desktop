export type ShortcutCategory = "SQL Editor" | "Data Grid" | "Navigation & App";

export type ShortcutItem = {
  category: ShortcutCategory;
  action: string;
  keys: string[];
  altKeys?: string[][];
  description?: string;
};

const isMac =
  typeof navigator !== "undefined" &&
  /Mac|iPhone|iPad/.test(navigator.platform);

export const modKey = isMac ? "⌘" : "Ctrl";

/** Flutter Preferences shortcuts reference (read-only catalog). */
export const allShortcuts: ShortcutItem[] = [
  {
    category: "SQL Editor",
    action: "Execute query / selection",
    keys: [modKey, "Enter"],
    altKeys: [[modKey, "R"]],
    description: "Runs statement under cursor or selected text",
  },
  {
    category: "SQL Editor",
    action: "Execute all statements",
    keys: [modKey, "Shift", "Enter"],
    altKeys: [["F5"]],
    description: "Runs the script one statement at a time",
  },
  {
    category: "SQL Editor",
    action: "New query tab",
    keys: [modKey, "T"],
    description: "Opens a new independent SQL tab session",
  },
  {
    category: "SQL Editor",
    action: "Close current tab",
    keys: [modKey, "W"],
  },
  {
    category: "SQL Editor",
    action: "Query history",
    keys: [modKey, "H"],
  },
  {
    category: "SQL Editor",
    action: "Format SQL statement",
    keys: ["Shift", "Alt", "F"],
  },
  {
    category: "Data Grid",
    action: "Copy cell value",
    keys: [modKey, "C"],
  },
  {
    category: "Data Grid",
    action: "Set cell to NULL",
    keys: ["Delete"],
    altKeys: [["Backspace"]],
  },
  {
    category: "Data Grid",
    action: "Toggle edit mode",
    keys: [modKey, "E"],
  },
  {
    category: "Data Grid",
    action: "Refresh results",
    keys: ["F5"],
  },
  {
    category: "Navigation & App",
    action: "Toggle sidebar",
    keys: [modKey, "B"],
  },
  {
    category: "Navigation & App",
    action: "Command palette",
    keys: [modKey, "P"],
  },
  {
    category: "Navigation & App",
    action: "Go to object",
    keys: [modKey, "K"],
  },
  {
    category: "Navigation & App",
    action: "Preferences",
    keys: [modKey, ","],
  },
  {
    category: "Navigation & App",
    action: "New connection",
    keys: [modKey, "N"],
  },
  {
    category: "Navigation & App",
    action: "Find in preferences",
    keys: [modKey, "F"],
    description: "Focuses the Preferences filter field",
  },
];

export const shortcutCategories = [
  "All",
  "SQL Editor",
  "Data Grid",
  "Navigation & App",
] as const satisfies ReadonlyArray<"All" | ShortcutCategory>;
