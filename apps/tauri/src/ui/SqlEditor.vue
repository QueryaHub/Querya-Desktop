<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from "vue";
import { EditorView, keymap, lineNumbers, placeholder } from "@codemirror/view";
import { Compartment, EditorState } from "@codemirror/state";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { sql } from "@codemirror/lang-sql";

const props = withDefaults(
  defineProps<{
    modelValue: string;
    disabled?: boolean;
  }>(),
  { disabled: false },
);

const emit = defineEmits<{
  "update:modelValue": [string];
  run: [];
}>();

const host = ref<HTMLDivElement | null>(null);
let view: EditorView | null = null;
const editable = new Compartment();

const theme = EditorView.theme({
  "&": {
    height: "100%",
    fontSize: "13px",
    backgroundColor: "var(--q-surface)",
    color: "var(--q-foreground)",
  },
  ".cm-content": {
    fontFamily: "var(--q-font-mono)",
    caretColor: "var(--q-primary)",
    padding: "8px 0",
  },
  ".cm-gutters": {
    backgroundColor: "var(--q-sidebar-bg)",
    color: "var(--q-muted-foreground)",
    borderRight:
      "1px solid color-mix(in srgb, var(--q-border) 60%, transparent)",
  },
  "&.cm-focused": { outline: "none" },
  ".cm-activeLine": {
    backgroundColor: "color-mix(in srgb, var(--q-primary) 8%, transparent)",
  },
  ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
    backgroundColor:
      "color-mix(in srgb, var(--q-primary) 28%, transparent) !important",
  },
});

function getRunnableSql(): string {
  if (!view) return props.modelValue;
  const sel = view.state.selection.main;
  if (!sel.empty) return view.state.sliceDoc(sel.from, sel.to);
  return view.state.doc.toString();
}

function run() {
  emit("update:modelValue", view?.state.doc.toString() ?? props.modelValue);
  emit("run");
}

onMounted(() => {
  if (!host.value) return;
  view = new EditorView({
    parent: host.value,
    state: EditorState.create({
      doc: props.modelValue,
      extensions: [
        lineNumbers(),
        history(),
        sql(),
        theme,
        placeholder("SELECT …  (Ctrl/Cmd+Enter to run)"),
        editable.of(EditorView.editable.of(!props.disabled)),
        keymap.of([
          {
            key: "Mod-Enter",
            run: () => {
              run();
              return true;
            },
          },
          ...defaultKeymap,
          ...historyKeymap,
        ]),
        EditorView.updateListener.of((u) => {
          if (u.docChanged) emit("update:modelValue", u.state.doc.toString());
        }),
      ],
    }),
  });
});

watch(
  () => props.modelValue,
  (next) => {
    if (!view) return;
    const cur = view.state.doc.toString();
    if (next !== cur) {
      view.dispatch({
        changes: { from: 0, to: cur.length, insert: next },
      });
    }
  },
);

watch(
  () => props.disabled,
  (disabled) => {
    view?.dispatch({
      effects: editable.reconfigure(EditorView.editable.of(!disabled)),
    });
  },
);

onBeforeUnmount(() => {
  view?.destroy();
  view = null;
});

defineExpose({ getRunnableSql, run });
</script>

<template>
  <div ref="host" class="sql-editor" data-testid="sql-editor" />
</template>

<style scoped>
.sql-editor {
  height: 100%;
  min-height: 120px;
  overflow: hidden;
  border: 1px solid
    color-mix(
      in srgb,
      var(--q-border) calc(var(--q-hairline-alpha) * 100%),
      transparent
    );
  border-radius: var(--q-radius-control);
  background: var(--q-surface);
}
</style>
