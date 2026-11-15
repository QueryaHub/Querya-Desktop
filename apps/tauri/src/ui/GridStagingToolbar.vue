<script setup lang="ts">
import { computed } from "vue";
import { storeToRefs } from "pinia";
import { useGridStagingStore } from "../stores/gridStaging";

const emit = defineEmits<{
  applied: [];
}>();

const staging = useGridStagingStore();
const {
  isDirty,
  changeCount,
  saving,
  applyError,
  canApply,
  selectedRowIndex,
  target,
} = storeToRefs(staging);

const hasTarget = computed(() => !!target.value);
const hasSelection = computed(
  () =>
    selectedRowIndex.value != null &&
    selectedRowIndex.value >= 0 &&
    selectedRowIndex.value < staging.rowCount,
);
const selectedDeleted = computed(
  () =>
    hasSelection.value &&
    staging.rowStatus(selectedRowIndex.value!) === "deleted",
);

function onRevert() {
  staging.revertAll();
}

async function onApply() {
  const ok = await staging.applyChanges();
  if (ok) emit("applied");
}
</script>

<template>
  <div
    class="staging-bar"
    data-testid="grid-staging-toolbar"
    :data-dirty="isDirty ? 'true' : 'false'"
  >
    <div class="row-actions">
      <button
        type="button"
        class="ghost"
        data-testid="staging-add-row"
        :disabled="saving || !hasTarget"
        title="Add new row"
        @click="staging.addRow()"
      >
        Add Row
      </button>
      <button
        type="button"
        class="ghost"
        :class="{ danger: hasSelection && !selectedDeleted }"
        data-testid="staging-delete-row"
        :disabled="saving || !hasSelection"
        :title="
          selectedDeleted
            ? 'Restore marked row'
            : hasSelection
              ? 'Mark row for deletion'
              : 'Select a row to delete'
        "
        @click="staging.toggleDeleteSelected()"
      >
        {{ selectedDeleted ? "Restore Row" : "Delete Row" }}
      </button>
    </div>

    <div class="commit">
      <span v-if="applyError" class="err" :title="applyError">{{
        applyError
      }}</span>
      <template v-if="isDirty">
        <span class="badge" data-testid="staging-pending-badge">
          {{ changeCount }} pending
        </span>
        <button
          type="button"
          class="secondary"
          data-testid="staging-revert"
          :disabled="saving"
          title="Discard all pending edits"
          @click="onRevert"
        >
          Revert All
        </button>
        <button
          type="button"
          class="primary"
          data-testid="staging-apply"
          :disabled="!canApply"
          :title="
            !target
              ? 'Open a table to save changes'
              : !target.primaryKeys.length
                ? 'Primary key required to save'
                : 'Save changes'
          "
          @click="onApply"
        >
          {{ saving ? "Saving…" : "Save Changes" }}
        </button>
      </template>
    </div>
  </div>
</template>

<style scoped>
.staging-bar {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 38px;
  padding: 0 8px 0 6px;
  flex-shrink: 0;
  background: var(--q-sidebar-bg);
  border-bottom: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
}

.row-actions {
  display: flex;
  align-items: center;
  gap: 2px;
  min-width: 0;
  flex: 1;
  overflow-x: auto;
}

.commit {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.badge {
  font-size: 11px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 4px;
  background: color-mix(in srgb, var(--q-accent, #22d3ee) 22%, transparent);
  color: var(--q-foreground);
}

.err {
  max-width: 220px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 11px;
  color: var(--q-danger, #ef4444);
}

button {
  font: inherit;
  font-size: 12px;
  border: none;
  border-radius: 4px;
  padding: 4px 10px;
  cursor: pointer;
  background: transparent;
  color: var(--q-foreground);
}

button:disabled {
  opacity: 0.45;
  cursor: default;
}

.ghost:hover:not(:disabled) {
  background: color-mix(in srgb, var(--q-foreground) 8%, transparent);
}

.ghost.danger {
  color: var(--q-danger, #ef4444);
}

.secondary {
  background: color-mix(in srgb, var(--q-foreground) 8%, transparent);
}

.secondary:hover:not(:disabled) {
  background: color-mix(in srgb, var(--q-foreground) 14%, transparent);
}

.primary {
  background: var(--q-accent, #22d3ee);
  color: #0c0c0c;
  font-weight: 600;
}

.primary:hover:not(:disabled) {
  filter: brightness(1.05);
}
</style>
