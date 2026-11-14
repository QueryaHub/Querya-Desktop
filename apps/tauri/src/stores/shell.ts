import { defineStore } from "pinia";
import { ref } from "vue";

/** Placeholder shell store — UI chrome lands in later issues. */
export const useShellStore = defineStore("shell", () => {
  const ready = ref(false);

  function markReady() {
    ready.value = true;
  }

  return { ready, markReady };
});
