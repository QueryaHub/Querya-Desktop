import {
  createElement,
  useCallback,
  useMemo,
  type ReactElement,
} from "react";
import {
  DataEditor,
  GridCellKind,
  type EditableGridCell,
  type GridCell,
  type Item,
  type Theme,
} from "@glideapps/glide-data-grid";
import type { StagedCellStatus, StagedRowStatus } from "../../staging/buffer";
import { sizeGlideColumns } from "./columnWidths";

export type ResultDataEditorProps = {
  columns: string[];
  /** Display rows (effective / query). */
  rows: unknown[][];
  width: number;
  height: number;
  /** Querya workbench → Glide theme (dark/light). */
  theme: Partial<Theme>;
  /** When true, cells are editable and dirty markers apply. */
  editable?: boolean;
  cellStatus?: (row: number, col: number) => StagedCellStatus;
  rowStatus?: (row: number) => StagedRowStatus;
  onCellEdited?: (row: number, col: number, value: string) => void;
};

function cellText(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return JSON.stringify(value);
}

const KEYBINDINGS = { search: true } as const;

export function ResultDataEditor(props: ResultDataEditorProps): ReactElement {
  const {
    columns,
    rows,
    width,
    height,
    theme,
    editable = false,
    cellStatus,
    rowStatus,
    onCellEdited,
  } = props;

  const gridColumns = useMemo(
    () => sizeGlideColumns({ columns, rows, viewportWidth: width }),
    [columns, rows, width],
  );

  const muted = theme.textMedium ?? theme.textLight ?? "#94a3b8";
  const stripeBg = theme.bgCellMedium;
  const accent = theme.accentColor ?? "#22d3ee";
  const surface = theme.bgCell ?? "#0c0c0c";

  const getCellContent = useCallback(
    ([col, row]: Item): GridCell => {
      const raw = rows[row]?.[col];
      const isNull =
        raw === null ||
        raw === undefined ||
        (typeof raw === "string" && raw === "NULL");
      const display = isNull ? "NULL" : cellText(raw);
      const data = isNull ? "" : cellText(raw);

      const staged = cellStatus?.(row, col) === "modified";
      const rowSt = rowStatus?.(row) ?? "unchanged";
      const themeOverride: Partial<Theme> = {};
      if (isNull) themeOverride.textDark = muted;
      if (staged) {
        themeOverride.bgCell = mixHex(surface, accent, 0.22);
      }
      if (rowSt === "deleted") {
        themeOverride.textDark = muted;
        themeOverride.bgCell = mixHex(surface, "#ef4444", 0.14);
      } else if (rowSt === "inserted") {
        themeOverride.bgCell = mixHex(
          staged ? (themeOverride.bgCell as string) || surface : surface,
          "#22c55e",
          0.14,
        );
      }

      return {
        kind: GridCellKind.Text,
        data,
        displayData: display,
        allowOverlay: true,
        readonly: !editable,
        themeOverride:
          Object.keys(themeOverride).length > 0 ? themeOverride : undefined,
      };
    },
    [rows, muted, accent, surface, editable, cellStatus, rowStatus],
  );

  const getRowThemeOverride = useCallback(
    (row: number): Partial<Theme> | undefined => {
      const rowSt = rowStatus?.(row) ?? "unchanged";
      if (rowSt === "deleted") {
        return { bgCell: mixHex(surface, "#ef4444", 0.1) };
      }
      if (rowSt === "inserted") {
        return { bgCell: mixHex(surface, "#22c55e", 0.1) };
      }
      if (rowSt === "modified") {
        return { bgCell: mixHex(surface, accent, 0.08) };
      }
      if (row % 2 === 0 || !stripeBg) return undefined;
      return { bgCell: stripeBg };
    },
    [stripeBg, rowStatus, surface, accent],
  );

  const handleCellEdited = useCallback(
    (cell: Item, newValue: EditableGridCell) => {
      if (!onCellEdited || !editable) return;
      const [col, row] = cell;
      if (newValue.kind !== GridCellKind.Text) return;
      onCellEdited(row, col, newValue.data);
    },
    [onCellEdited, editable],
  );

  return createElement(DataEditor, {
    columns: gridColumns,
    rows: rows.length,
    getCellContent,
    getRowThemeOverride,
    onCellEdited: editable ? handleCellEdited : undefined,
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

function parseRgb(hex: string): [number, number, number] | null {
  const m = /^#([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return null;
  const n = parseInt(m[1]!, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function mixHex(base: string, overlay: string, alpha: number): string {
  const b = parseRgb(base);
  const o = parseRgb(overlay.startsWith("#") ? overlay : `#${overlay}`);
  if (!b || !o) return base;
  const mix = (x: number, y: number) => Math.round(x * (1 - alpha) + y * alpha);
  const r = mix(b[0], o[0]);
  const g = mix(b[1], o[1]);
  const bl = mix(b[2], o[2]);
  return `#${((1 << 24) | (r << 16) | (g << 8) | bl).toString(16).slice(1)}`;
}
