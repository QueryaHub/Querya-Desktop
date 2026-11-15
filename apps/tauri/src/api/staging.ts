import { invoke } from "@tauri-apps/api/core";

export type StagingApplyRequest = {
  connectionId: string;
  tableName: string;
  schema?: string | null;
  columns: string[];
  primaryKeys: string[];
  originalRows: string[][];
  modifiedCells: { row: number; col: number; value: string }[];
  insertedRows: string[][];
  deletedRowIndices: number[];
};

export type ApplyResult = {
  statements_applied: number;
};

/** Apply staged grid edits in one DB transaction. */
export async function dbApplyStaging(
  request: StagingApplyRequest,
): Promise<ApplyResult> {
  return invoke<ApplyResult>("db_apply_staging", { request });
}
