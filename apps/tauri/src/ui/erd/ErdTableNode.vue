<script setup lang="ts">
import { Handle, Position, type NodeProps } from "@vue-flow/core";
import type { ErdTableNodeData } from "./layout";

const props = defineProps<NodeProps<ErdTableNodeData>>();

const table = props.data.table;
</script>

<template>
  <div
    class="erd-table"
    :class="{ view: table.isView, selected }"
    data-testid="erd-table-node"
  >
    <header class="head">
      <span class="ico" aria-hidden="true">{{ table.isView ? "◇" : "▥" }}</span>
      <span class="name">{{ table.name }}</span>
    </header>
    <ul class="cols">
      <li
        v-for="col in table.columns"
        :key="col.name"
        class="col"
        :class="{
          pk: col.isPrimaryKey,
          fk: col.isForeignKey,
        }"
      >
        <Handle
          :id="`in-${col.name}`"
          type="target"
          :position="Position.Left"
          class="handle"
        />
        <span class="markers">
          <span v-if="col.isPrimaryKey" class="mk pk" title="Primary key">PK</span>
          <span v-if="col.isForeignKey" class="mk fk" title="Foreign key">FK</span>
        </span>
        <span class="cname">{{ col.name }}</span>
        <span class="ctype">{{ col.dataType }}</span>
        <Handle
          :id="`out-${col.name}`"
          type="source"
          :position="Position.Right"
          class="handle"
        />
      </li>
    </ul>
  </div>
</template>

<style scoped>
.erd-table {
  width: 260px;
  background: var(--q-card);
  border: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100% + 40%),
      transparent
    );
  border-radius: var(--q-radius-md);
  box-shadow: var(--q-shadow-sm);
  font-size: var(--q-text-xs);
  color: var(--q-card-foreground);
  overflow: hidden;
}

.erd-table.selected {
  border-color: var(--q-primary);
  box-shadow: 0 0 0 1px var(--q-primary);
}

.erd-table.view .head {
  background: color-mix(in srgb, var(--q-accent) 70%, var(--q-card));
}

.head {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 10px;
  background: color-mix(in srgb, var(--q-primary) 12%, var(--q-card));
  border-bottom: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  font-weight: 600;
  font-size: var(--q-text-sm);
}

.ico {
  opacity: 0.7;
}

.name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.cols {
  list-style: none;
  margin: 0;
  padding: 4px 0;
}

.col {
  position: relative;
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  gap: 4px;
  padding: 3px 12px;
  min-height: 22px;
  font-family: var(--q-font-mono);
}

.col.pk {
  background: color-mix(in srgb, var(--q-warning) 8%, transparent);
}

.markers {
  display: flex;
  gap: 2px;
  min-width: 28px;
}

.mk {
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.02em;
  padding: 0 3px;
  border-radius: 2px;
  line-height: 1.4;
}

.mk.pk {
  color: var(--q-warning);
  background: color-mix(in srgb, var(--q-warning) 18%, transparent);
}

.mk.fk {
  color: var(--q-primary);
  background: color-mix(in srgb, var(--q-primary) 16%, transparent);
}

.cname {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ctype {
  color: var(--q-muted-foreground);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 90px;
  text-align: right;
}

.handle {
  width: 6px !important;
  height: 6px !important;
  background: var(--q-primary) !important;
  border: 1px solid var(--q-card) !important;
  opacity: 0.55;
}
</style>
