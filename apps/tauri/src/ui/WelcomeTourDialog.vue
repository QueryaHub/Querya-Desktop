<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";

const props = defineProps<{ open: boolean }>();
const emit = defineEmits<{
  close: [];
  launchDemo: [];
  openPreferences: [];
}>();

const slides = [
  {
    title: "Welcome to Querya",
    body: "A lightweight desktop client for SQL and NoSQL — built around Fluid Motion and Liquid Glass.",
  },
  {
    title: "Servers sidebar",
    body: "Browse connections on the left. Expand a server to see tables and views, then click an object to open its Data grid.",
  },
  {
    title: "Command palette",
    body: "Press Ctrl/Cmd+P to run any app command. Ctrl/Cmd+K jumps straight to a table or view.",
  },
  {
    title: "Preferences",
    body: "Ctrl/Cmd+, opens Preferences — theme, Fluid Motion, editor, data grid limits, and more.",
  },
  {
    title: "Demo playground",
    body: "Try the offline Demo catalog to explore the UI without connecting to a real database.",
  },
  {
    title: "You’re set",
    body: "Launch Demo, open a SQLite file, or create a connection when you’re ready.",
  },
];

const index = ref(0);
const isLast = computed(() => index.value >= slides.length - 1);
const slide = computed(() => slides[index.value]!);

watch(
  () => props.open,
  (v) => {
    if (v) index.value = 0;
  },
);

function next() {
  if (isLast.value) {
    emit("close");
    return;
  }
  index.value += 1;
}

function back() {
  index.value = Math.max(0, index.value - 1);
}

function onKey(e: KeyboardEvent) {
  if (!props.open) return;
  if (e.key === "Escape") {
    e.preventDefault();
    emit("close");
  } else if (e.key === "ArrowRight" || e.key === "Enter") {
    e.preventDefault();
    next();
  } else if (e.key === "ArrowLeft") {
    e.preventDefault();
    back();
  }
}

onMounted(() => window.addEventListener("keydown", onKey));
onUnmounted(() => window.removeEventListener("keydown", onKey));
</script>

<template>
  <div
    v-if="open"
    class="overlay"
    data-testid="welcome-tour"
    @click.self="emit('close')"
  >
    <div class="card q-glass" role="dialog" aria-modal="true" :aria-label="slide.title">
      <header class="head">
        <p class="step">{{ index + 1 }} / {{ slides.length }}</p>
        <button type="button" class="x" aria-label="Close" @click="emit('close')">
          ✕
        </button>
      </header>
      <h2>{{ slide.title }}</h2>
      <p class="body">{{ slide.body }}</p>
      <div class="dots" aria-hidden="true">
        <span
          v-for="(_, i) in slides"
          :key="i"
          class="dot"
          :class="{ on: i === index }"
        />
      </div>
      <footer class="foot">
        <button
          v-if="index === slides.length - 2 || isLast"
          type="button"
          class="ghost"
          @click="emit('launchDemo'); emit('close')"
        >
          Launch Demo
        </button>
        <div class="spacer" />
        <button
          v-if="index > 0"
          type="button"
          class="ghost"
          @click="back"
        >
          Back
        </button>
        <button type="button" class="primary" @click="next">
          {{ isLast ? "Done" : "Next" }}
        </button>
      </footer>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 2200;
  display: grid;
  place-items: center;
  background: color-mix(in srgb, #000 45%, transparent);
  padding: 24px;
}

.card {
  width: min(440px, 100%);
  border-radius: 14px;
  border: 1px solid var(--q-border);
  background: var(--q-surface);
  padding: 18px 20px 16px;
}

.head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.step {
  margin: 0;
  font-size: 11px;
  color: var(--q-muted-foreground);
  font-family: var(--q-font-mono);
}

.x {
  appearance: none;
  border: 0;
  background: transparent;
  width: 28px;
  height: 28px;
  border-radius: var(--q-radius-sm);
  color: var(--q-muted-foreground);
  cursor: pointer;
}

.x:hover {
  background: var(--q-accent);
  color: var(--q-foreground);
}

h2 {
  margin: 0 0 8px;
  font-size: 18px;
  font-weight: 650;
  letter-spacing: -0.02em;
}

.body {
  margin: 0;
  font-size: 13px;
  line-height: 1.5;
  color: var(--q-muted-foreground);
  min-height: 4.5rem;
}

.dots {
  display: flex;
  gap: 6px;
  margin: 16px 0;
}

.dot {
  width: 6px;
  height: 6px;
  border-radius: 999px;
  background: var(--q-border);
}

.dot.on {
  background: var(--q-primary);
}

.foot {
  display: flex;
  align-items: center;
  gap: 8px;
}

.spacer {
  flex: 1;
}

.primary,
.ghost {
  appearance: none;
  height: 30px;
  padding: 0 12px;
  border-radius: var(--q-radius-control);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}

.primary {
  border: 0;
  background: var(--q-primary);
  color: var(--q-primary-foreground);
  font-weight: 600;
}

.ghost {
  border: 1px solid var(--q-border);
  background: transparent;
  color: var(--q-foreground);
}

.ghost:hover {
  background: var(--q-accent);
}
</style>
