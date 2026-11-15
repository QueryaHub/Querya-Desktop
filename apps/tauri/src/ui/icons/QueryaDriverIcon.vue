<script setup lang="ts">
import { computed, ref } from "vue";
import QueryaIcon from "./QueryaIcon.vue";
import { iconForDriver } from "./objectKind";
import { connectionAsset, type QueryaIconName } from "./registry";

const props = withDefaults(
  defineProps<{
    driver: string;
    mock?: boolean;
    size?: number;
  }>(),
  { size: 14, mock: false },
);

const broken = ref(false);

const asset = computed(() =>
  props.mock ? null : connectionAsset(props.driver),
);

/** Flutter `QueryaIcons.connectionIcon` fallbacks when no PNG. */
const fallback = computed<QueryaIconName>(() =>
  iconForDriver(props.driver, { mock: props.mock }),
);

const isMysql = computed(
  () => props.driver === "mysql" && !!asset.value && !broken.value,
);
</script>

<template>
  <img
    v-if="asset && !broken"
    class="q-driver-icon"
    :class="{ mysql: isMysql }"
    :src="asset"
    alt=""
    :width="size"
    :height="size"
    draggable="false"
    @error="broken = true"
  />
  <QueryaIcon v-else :name="fallback" :size="size" class="q-driver-fallback" />
</template>

<style scoped>
.q-driver-icon {
  flex-shrink: 0;
  object-fit: contain;
  display: block;
}

/* Flutter DriverIcon #1824 — only when tokens are actually dark (tokens.css). */
:root[data-theme="dark"] .q-driver-icon.mysql {
  filter: brightness(1.9) contrast(1.05);
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) .q-driver-icon.mysql {
    filter: brightness(1.9) contrast(1.05);
  }
}

.q-driver-fallback {
  color: var(--q-primary);
}
</style>
