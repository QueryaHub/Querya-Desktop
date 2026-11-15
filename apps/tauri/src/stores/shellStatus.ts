import { defineStore } from "pinia";
import { ref } from "vue";

/** Flutter QueryaShellStatus — workspaces publish busy/metrics here. */
export const useShellStatusStore = defineStore("shellStatus", () => {
  const statusMessage = ref<string | null>(null);
  const isBusy = ref(false);
  const rowCount = ref<number | null>(null);
  const columnCount = ref<number | null>(null);
  const lastQueryMs = ref<number | null>(null);
  const connectionName = ref<string | null>(null);
  const connectionHost = ref<string | null>(null);
  const isReadOnly = ref(false);

  function clear() {
    statusMessage.value = null;
    isBusy.value = false;
    rowCount.value = null;
    columnCount.value = null;
    lastQueryMs.value = null;
  }

  function setConnection(name: string | null, host: string | null = null) {
    connectionName.value = name;
    connectionHost.value = host;
    if (!name) clear();
  }

  function setQueryMetrics(opts: {
    message?: string | null;
    busy?: boolean;
    rows?: number | null;
    cols?: number | null;
    durationMs?: number | null;
  }) {
    if (opts.message !== undefined) statusMessage.value = opts.message;
    if (opts.busy !== undefined) isBusy.value = opts.busy;
    if (opts.rows !== undefined) rowCount.value = opts.rows;
    if (opts.cols !== undefined) columnCount.value = opts.cols;
    if (opts.durationMs !== undefined) lastQueryMs.value = opts.durationMs;
  }

  return {
    statusMessage,
    isBusy,
    rowCount,
    columnCount,
    lastQueryMs,
    connectionName,
    connectionHost,
    isReadOnly,
    clear,
    setConnection,
    setQueryMetrics,
  };
});
