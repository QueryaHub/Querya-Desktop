/** Frontend staging buffer — Flutter / Rust `StagingBuffer` parity (cell layer). */

export const NULL_SENTINEL = "\u0000__QUERYA_NULL__\u0000";

export type StagedRowStatus =
  | "unchanged"
  | "modified"
  | "inserted"
  | "deleted";

export type StagedCellStatus = "clean" | "modified";

export class StagingBuffer {
  private columns: string[];
  private originalRows: string[][];
  private primaryKeys: string[];
  private modifiedCells = new Map<number, Map<number, string>>();
  private insertedRows: string[][] = [];
  private deletedRowIndices = new Set<number>();
  private revision = 0;

  constructor(
    columns: string[],
    rows: string[][],
    primaryKeys: string[] = [],
  ) {
    this.columns = [...columns];
    this.originalRows = rows.map((r) => [...r]);
    this.primaryKeys = [...primaryKeys];
  }

  /** Replace baseline (e.g. after a new query) and clear staged edits. */
  replaceBaseline(
    columns: string[],
    rows: string[][],
    primaryKeys: string[] = [],
  ): void {
    this.columns = [...columns];
    this.originalRows = rows.map((r) => [...r]);
    this.primaryKeys = [...primaryKeys];
    this.modifiedCells.clear();
    this.insertedRows = [];
    this.deletedRowIndices.clear();
    this.revision += 1;
  }

  getRevision(): number {
    return this.revision;
  }

  getColumns(): string[] {
    return this.columns;
  }

  getPrimaryKeys(): string[] {
    return this.primaryKeys;
  }

  totalRowCount(): number {
    return this.originalRows.length + this.insertedRows.length;
  }

  isDirty(): boolean {
    return (
      this.modifiedCells.size > 0 ||
      this.insertedRows.length > 0 ||
      this.deletedRowIndices.size > 0
    );
  }

  changeCount(): number {
    let cells = 0;
    for (const m of this.modifiedCells.values()) cells += m.size;
    return cells + this.insertedRows.length + this.deletedRowIndices.size;
  }

  getCellValue(row: number, col: number): string {
    if (row < this.originalRows.length) {
      const staged = this.modifiedCells.get(row)?.get(col);
      if (staged !== undefined) return sanitizeNull(staged);
      return this.originalRows[row]?.[col] ?? "";
    }
    const insertIdx = row - this.originalRows.length;
    return sanitizeNull(this.insertedRows[insertIdx]?.[col] ?? "");
  }

  rowStatus(row: number): StagedRowStatus {
    if (row >= this.originalRows.length) {
      return row < this.totalRowCount() ? "inserted" : "unchanged";
    }
    if (this.deletedRowIndices.has(row)) return "deleted";
    const mods = this.modifiedCells.get(row);
    if (mods && mods.size > 0) return "modified";
    return "unchanged";
  }

  cellStatus(row: number, col: number): StagedCellStatus {
    if (
      row < this.originalRows.length &&
      this.modifiedCells.get(row)?.has(col)
    ) {
      return "modified";
    }
    return "clean";
  }

  setCell(row: number, col: number, value: string): void {
    if (row < 0 || col < 0) return;
    if (row < this.originalRows.length) {
      const orig = this.originalRows[row]?.[col] ?? "";
      if (value === orig) {
        const map = this.modifiedCells.get(row);
        if (map) {
          map.delete(col);
          if (map.size === 0) this.modifiedCells.delete(row);
          this.revision += 1;
        }
      } else {
        let map = this.modifiedCells.get(row);
        if (!map) {
          map = new Map();
          this.modifiedCells.set(row, map);
        }
        if (map.get(col) !== value) {
          map.set(col, value);
          this.revision += 1;
        }
      }
      return;
    }
    const insertIdx = row - this.originalRows.length;
    const ins = this.insertedRows[insertIdx];
    if (!ins) return;
    while (ins.length <= col) ins.push("");
    if (ins[col] !== value) {
      ins[col] = value;
      this.revision += 1;
    }
  }

  setCellNull(row: number, col: number): void {
    this.setCell(row, col, NULL_SENTINEL);
  }

  toggleDeleteRow(row: number): void {
    if (row < 0) return;
    if (row < this.originalRows.length) {
      if (this.deletedRowIndices.has(row)) this.deletedRowIndices.delete(row);
      else this.deletedRowIndices.add(row);
      this.revision += 1;
    } else {
      const insertIdx = row - this.originalRows.length;
      if (insertIdx >= 0 && insertIdx < this.insertedRows.length) {
        this.insertedRows.splice(insertIdx, 1);
        this.revision += 1;
      }
    }
  }

  revertAll(): void {
    if (!this.isDirty()) return;
    this.modifiedCells.clear();
    this.insertedRows = [];
    this.deletedRowIndices.clear();
    this.revision += 1;
  }

  /** Effective grid values (deleted rows kept for strike-through). */
  effectiveRows(): string[][] {
    const out: string[][] = [];
    for (let r = 0; r < this.originalRows.length; r++) {
      const mods = this.modifiedCells.get(r);
      if (mods) {
        const row = [...(this.originalRows[r] ?? [])];
        for (const [c, v] of mods) {
          if (c < row.length) row[c] = sanitizeNull(v);
        }
        out.push(row);
      } else {
        out.push([...(this.originalRows[r] ?? [])]);
      }
    }
    for (const ins of this.insertedRows) {
      out.push(ins.map(sanitizeNull));
    }
    return out;
  }
}

function sanitizeNull(value: string): string {
  return value === NULL_SENTINEL ? "NULL" : value;
}

/** Coerce query result cells to staging strings. */
export function rowsToStrings(rows: unknown[][]): string[][] {
  return rows.map((row) =>
    row.map((cell) => {
      if (cell === null || cell === undefined) return "NULL";
      if (typeof cell === "string") return cell;
      if (typeof cell === "number" || typeof cell === "boolean") {
        return String(cell);
      }
      return JSON.stringify(cell);
    }),
  );
}
