import { defineStore } from "pinia";
import { computed, ref } from "vue";
import { rowsToStrings, StagingBuffer } from "../staging/buffer";

/**
 * Pinia façade over {@link StagingBuffer} for the result grid.
 * Apply / discard IPC lands in #1891; this store owns dirty markers (#1890).
 */
export const useGridStagingStore = defineStore("gridStaging", () => {
  const buffer = ref<StagingBuffer | null>(null);
  /** Mirrors buffer revision so Vue / Glide can watch cheaply. */
  const revision = ref(0);

  const isDirty = computed(() => buffer.value?.isDirty() ?? false);
  const changeCount = computed(() => buffer.value?.changeCount() ?? 0);
  const rowCount = computed(() => buffer.value?.totalRowCount() ?? 0);

  function bump() {
    revision.value = buffer.value?.getRevision() ?? 0;
  }

  function attachFromQuery(columns: string[], rows: unknown[][]) {
    const stringRows = rowsToStrings(rows);
    if (!buffer.value) {
      buffer.value = new StagingBuffer(columns, stringRows);
    } else {
      buffer.value.replaceBaseline(columns, stringRows);
    }
    bump();
  }

  function clear() {
    buffer.value = null;
    revision.value = 0;
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

  function revertAll() {
    buffer.value?.revertAll();
    bump();
  }

  return {
    revision,
    isDirty,
    changeCount,
    rowCount,
    attachFromQuery,
    clear,
    setCell,
    cellStatus,
    rowStatus,
    getCellValue,
    effectiveRows,
    revertAll,
  };
});
