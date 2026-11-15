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
  type GridColumn,
  type Item,
} from "@glideapps/glide-data-grid";

export type ResultDataEditorProps = {
  columns: string[];
  rows: unknown[][];
  width: number;
  height: number;
};

function cellText(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return JSON.stringify(value);
}

export function ResultDataEditor(props: ResultDataEditorProps): ReactElement {
  const { columns, rows, width, height } = props;

  const gridColumns: GridColumn[] = useMemo(
    () =>
      columns.map((title) => ({
        id: title,
        title,
        width: Math.min(280, Math.max(96, title.length * 9 + 40)),
      })),
    [columns],
  );

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
        themeOverride: isNull
          ? { textDark: "var(--q-muted-foreground)" }
          : undefined,
      };
    },
    [rows],
  );

  return createElement(DataEditor, {
    columns: gridColumns,
    rows: rows.length,
    getCellContent,
    width,
    height,
    rowMarkers: "number",
    smoothScrollX: true,
    smoothScrollY: true,
    getCellsForSelection: true,
    keybindings: { search: true },
  });
}
