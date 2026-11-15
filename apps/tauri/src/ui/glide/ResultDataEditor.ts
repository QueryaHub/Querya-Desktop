import {
  createElement,
  useCallback,
  useMemo,
  type ReactElement,
} from "react";
import {
  DataEditor,
  GridCellKind,
  type GridCell,
  type Item,
  type Theme,
} from "@glideapps/glide-data-grid";
import { sizeGlideColumns } from "./columnWidths";

export type ResultDataEditorProps = {
  columns: string[];
  rows: unknown[][];
  width: number;
  height: number;
  /** Querya workbench → Glide theme (dark/light). */
  theme: Partial<Theme>;
};

function cellText(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return JSON.stringify(value);
}

const KEYBINDINGS = { search: true } as const;

export function ResultDataEditor(props: ResultDataEditorProps): ReactElement {
  const { columns, rows, width, height, theme } = props;

  const gridColumns = useMemo(
    () => sizeGlideColumns({ columns, rows, viewportWidth: width }),
    [columns, rows, width],
  );

  const muted = theme.textMedium ?? theme.textLight ?? "#94a3b8";

  const getCellContent = useCallback(
    ([col, row]: Item): GridCell => {
      const raw = rows[row]?.[col];
      const isNull = raw === null || raw === undefined;
      return {
        kind: GridCellKind.Text,
        data: isNull ? "" : cellText(raw),
        displayData: isNull ? "NULL" : cellText(raw),
        allowOverlay: true,
        readonly: true,
        themeOverride: isNull ? { textDark: muted } : undefined,
      };
    },
    [rows, muted],
  );

  return createElement(DataEditor, {
    columns: gridColumns,
    rows: rows.length,
    getCellContent,
    width,
    height,
    theme,
    rowMarkers: "number",
    smoothScrollX: true,
    smoothScrollY: true,
    getCellsForSelection: true,
    keybindings: KEYBINDINGS,
    maxColumnWidth: 600,
    minColumnWidth: 56,
  });
}
