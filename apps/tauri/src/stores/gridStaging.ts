import { defineStore } from "pinia";
import { computed, ref } from "vue";
import { dbApplyStaging } from "../api/staging";
import { formatConnectionError } from "../api/connection";
import { rowsToStrings, StagingBuffer } from "../staging/buffer";

export type StagingTableTarget = {
  connectionId: string;
  tableName: string;
  schema?: string | null;
  primaryKeys: string[];
};

/**
 * Pinia façade over {@link StagingBuffer} for the result grid.
 * Dirty markers (#1890); apply / discard IPC (#1891).
 */
export const useGridStagingStore = defineStore("gridStaging", () => {
  const buffer = ref<StagingBuffer | null>(null);
  /** Mirrors buffer revision so Vue / Glide can watch cheaply. */
  const revision = ref(0);
  const target = ref<StagingTableTarget | null>(null);
  const saving = ref(false);
  const applyError = ref<string | null>(null);
  const selectedRowIndex = ref<number | null>(null);

  const isDirty = computed(() => buffer.value?.isDirty() ?? false);
  const changeCount = computed(() => buffer.value?.changeCount() ?? 0);
  const rowCount = computed(() => buffer.value?.totalRowCount() ?? 0);
  const canApply = computed(
    () =>
      isDirty.value &&
      !!target.value &&
      target.value.primaryKeys.length > 0 &&
      !saving.value,
  );

  function bump() {
    revision.value = buffer.value?.getRevision() ?? 0;
  }

  function setTarget(next: StagingTableTarget | null) {
    target.value = next;
    if (next && buffer.value) {
      buffer.value.setPrimaryKeys(next.primaryKeys);
      bump();
    }
  }

  function attachFromQuery(columns: string[], rows: unknown[][]) {
    const stringRows = rowsToStrings(rows);
    const pks = target.value?.primaryKeys ?? [];
    if (!buffer.value) {
      buffer.value = new StagingBuffer(columns, stringRows, pks);
    } else {
      buffer.value.replaceBaseline(columns, stringRows, pks);
    }
    applyError.value = null;
    bump();
  }

  function clear() {
    buffer.value = null;
    revision.value = 0;
    applyError.value = null;
    selectedRowIndex.value = null;
  }

  function setCell(row: number, col: number, value: string) {
    buffer.value?.setCell(row, col, value);
    bump();
  }

  function cellStatus(row: number, col: number) {
    return buffer.value?.cellStatus(row, col) ?? "clean";
  }

  function rowStatus(row: number) {
    return buffer.value?.rowStatus(row) ?? "unchanged";
  }

  function getCellValue(row: number, col: number) {
    return buffer.value?.getCellValue(row, col) ?? "";
  }

  function effectiveRows(): string[][] {
    return buffer.value?.effectiveRows() ?? [];
  }

  function addRow() {
    buffer.value?.addRow();
    bump();
  }

  function toggleDeleteSelected() {
    const row = selectedRowIndex.value;
    if (row == null) return;
    buffer.value?.toggleDeleteRow(row);
    bump();
  }

  function revertAll() {
    buffer.value?.revertAll();
    applyError.value = null;
    bump();
  }

  async function applyChanges(): Promise<boolean> {
    const buf = buffer.value;
    const t = target.value;
    if (!buf || !t || !buf.isDirty()) return false;
    if (t.primaryKeys.length === 0) {
      applyError.value = "Primary key required to save changes";
      return false;
    }
    saving.value = true;
    applyError.value = null;
    try {
      const snap = buf.toApplySnapshot();
      const result = await dbApplyStaging({
        connectionId: t.connectionId,
        tableName: t.tableName,
        schema: t.schema ?? null,
        columns: snap.columns,
        primaryKeys: snap.primaryKeys.length ? snap.primaryKeys : t.primaryKeys,
        originalRows: snap.originalRows,
        modifiedCells: snap.modifiedCells,
        insertedRows: snap.insertedRows,
        deletedRowIndices: snap.deletedRowIndices,
      });
      buf.revertAll();
      bump();
      return result.statements_applied >= 0;
    } catch (err) {
      applyError.value = formatConnectionError(err);
      return false;
    } finally {
      saving.value = false;
    }
  }

  return {
    revision,
    isDirty,
    changeCount,
    rowCount,
    target,
    saving,
    applyError,
    selectedRowIndex,
    canApply,
    setTarget,
    attachFromQuery,
    clear,
    setCell,
    cellStatus,
    rowStatus,
    getCellValue,
    effectiveRows,
    addRow,
    toggleDeleteSelected,
    revertAll,
    applyChanges,
  };
});
