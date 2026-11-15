<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import { DEMO_CONNECTION } from "../mock/demoCatalog";
import { useConnectionsStore } from "../stores/connections";
import { useObjectTreeStore } from "../stores/objectTree";
import { useShellNavStore } from "../stores/shellNav";

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: [] }>();

const connections = useConnectionsStore();
const tree = useObjectTreeStore();
const nav = useShellNavStore();

const query = ref("");
const selected = ref(0);
const input = ref<HTMLInputElement | null>(null);

type Hit = {
  connectionId: string;
  name: string;
  kind: "table" | "view" | "materialized_view";
  connectionName: string;
};

const hits = computed(() => {
  const q = query.value.trim().toLowerCase();
  const out: Hit[] = [];
  for (const c of connections.items) {
    const objs =
      c.mock
        ? DEMO_CONNECTION.objects
        : c.id === tree.connectionId
          ? tree.relations
          : [];
    for (const o of objs) {
      if (q && !o.name.toLowerCase().includes(q)) continue;
      out.push({
        connectionId: c.id,
        name: o.name,
        kind: o.kind as "table" | "view" | "materialized_view",
        connectionName: c.name,
      });
    }
  }
  return out.slice(0, 50);
});

watch(
  () => props.open,
  async (v) => {
    if (!v) return;
    query.value = "";
    selected.value = 0;
    await nextTick();
    input.value?.focus();
  },
);

watch(hits, () => {
  selected.value = 0;
});

function openHit() {
  const hit = hits.value[selected.value];
  if (!hit) return;
  emit("close");
  connections.select(hit.connectionId);
  nav.setExpanded(hit.connectionId, true);
  nav.selectObject({
    connectionId: hit.connectionId,
    name: hit.name,
    kind: hit.kind,
  });
}

function onKey(e: KeyboardEvent) {
  if (!props.open) return;
  if (e.key === "Escape") {
    e.preventDefault();
    emit("close");
  } else if (e.key === "ArrowDown") {
    e.preventDefault();
    selected.value = Math.min(selected.value + 1, hits.value.length - 1);
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    selected.value = Math.max(selected.value - 1, 0);
  } else if (e.key === "Enter") {
    e.preventDefault();
    openHit();
  }
}

onMounted(() => window.addEventListener("keydown", onKey, true));
onUnmounted(() => window.removeEventListener("keydown", onKey, true));
</script>

<template>
  <div
    v-if="open"
    class="overlay q-modal-scrim"
    data-testid="quick-switcher"
    @click.self="emit('close')"
  >
    <div class="panel q-glass" role="dialog" aria-label="Go to object">
      <input
        ref="input"
        v-model="query"
        class="query"
        type="search"
        placeholder="Go to table or view…"
        aria-label="Filter objects"
      />
      <ul class="list">
        <li v-if="!hits.length" class="empty">
          {{
            connections.items.length
              ? "No matching objects"
              : "Launch Demo or open a connection first"
          }}
        </li>
        <li
          v-for="(hit, i) in hits"
          :key="`${hit.connectionId}:${hit.name}`"
          class="item"
          :class="{ on: i === selected }"
          @mouseenter="selected = i"
          @click="openHit()"
        >
          <span class="name">{{ hit.name }}</span>
          <span class="meta">{{ hit.kind }} · {{ hit.connectionName }}</span>
        </li>
      </ul>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 2100;
  display: grid;
  place-items: start center;
  padding-top: 12vh;
}

.panel {
  width: min(520px, 92vw);
  border-radius: 12px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  overflow: hidden;
  box-shadow: 0 18px 48px color-mix(in srgb, #000 45%, transparent);
}

.query {
  width: 100%;
  height: 44px;
  border: 0;
  border-bottom: 1px solid
    color-mix(in srgb, var(--q-border) 70%, transparent);
  background: transparent;
  color: var(--q-foreground);
  padding: 0 16px;
  font: inherit;
  font-size: 14px;
  outline: none;
}

.list {
  list-style: none;
  margin: 0;
  padding: 6px;
  max-height: 320px;
  overflow: auto;
}

.item {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 8px 10px;
  border-radius: var(--q-radius-control);
  cursor: pointer;
  font-size: 13px;
}

.item.on,
.item:hover {
  background: color-mix(in srgb, var(--q-primary) 16%, transparent);
}

.name {
  font-weight: 500;
}

.meta {
  font-size: 11px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.empty {
  padding: 16px;
  text-align: center;
  color: var(--q-muted-foreground);
  font-size: 12px;
}
</style>
