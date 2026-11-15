<script setup lang="ts">
import { ref, watch } from "vue";
import {
  dbErdSchema,
  formatConnectionError,
  type ErdSchema,
} from "../../api/connection";
import { demoErdSchema } from "../../mock/demoCatalog";
import ErdCanvas from "./ErdCanvas.vue";

const props = defineProps<{
  connectionId: string;
  /** When set, load only FK neighbourhood (depth hops). */
  focus?: string | null;
  depth?: number;
  /** Offline demo connection — no IPC. */
  mock?: boolean;
  schema?: string | null;
}>();

const catalog = ref<ErdSchema | null>(null);
const loading = ref(false);
const error = ref<string | null>(null);

async function load() {
  loading.value = true;
  error.value = null;
  try {
    if (props.mock) {
      catalog.value = demoErdSchema({
        focus: props.focus ?? null,
        depth: props.depth ?? 1,
      });
      return;
    }
    catalog.value = await dbErdSchema(props.connectionId, {
      schema: props.schema ?? null,
      focus: props.focus ?? null,
      depth: props.focus ? (props.depth ?? 1) : null,
    });
  } catch (err) {
    catalog.value = null;
    error.value = formatConnectionError(err);
  } finally {
    loading.value = false;
  }
}

watch(
  () =>
    [
      props.connectionId,
      props.focus,
      props.depth,
      props.mock,
      props.schema,
    ] as const,
  () => {
    void load();
  },
  { immediate: true },
);

defineExpose({ reload: load });
</script>

<template>
  <div class="erd-view" data-testid="erd-view">
    <ErdCanvas :schema="catalog" :loading="loading" :error="error" />
  </div>
</template>

<style scoped>
.erd-view {
  height: 100%;
  min-height: 0;
}
</style>
