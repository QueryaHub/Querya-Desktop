import {
  computed,
  inject,
  onScopeDispose,
  provide,
  ref,
  type InjectionKey,
  type Ref,
} from "vue";
import {
  effectiveDurationMs,
  effectiveEasing,
  QueryaMotionEasing,
  QueryaMotionMs,
  springsEnabled,
  type QueryaMotionToken,
} from "./tokens";
import type { QueryaMotionLevel } from "./types";

const STORAGE_KEY = "querya.motion";

type MotionApi = {
  level: Ref<QueryaMotionLevel>;
  /** True when the user picked Full/Reduced/Off (not following OS). */
  manual: Ref<boolean>;
  setLevel: (level: QueryaMotionLevel) => void;
  /** Clear override and follow prefers-reduced-motion again. */
  followSystem: () => void;
  duration: (token?: QueryaMotionToken | number) => number;
  easing: (name?: keyof typeof QueryaMotionEasing) => string;
  springsOn: Ref<boolean>;
};

const MotionKey: InjectionKey<MotionApi> = Symbol("querya-motion");

function prefersReducedMotion(): boolean {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function levelFromSystem(): QueryaMotionLevel {
  return prefersReducedMotion() ? "reduced" : "full";
}

function readStoredLevel(): QueryaMotionLevel | null {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (raw === "full" || raw === "reduced" || raw === "off") return raw;
  return null;
}

function applyDom(next: QueryaMotionLevel) {
  document.documentElement.dataset.motion = next;
}

export function provideQueryaMotion(
  initial?: QueryaMotionLevel,
): MotionApi {
  const stored = readStoredLevel();
  const manual = ref(stored !== null);
  const level = ref<QueryaMotionLevel>(
    initial ?? stored ?? levelFromSystem(),
  );

  applyDom(level.value);

  function setLevel(next: QueryaMotionLevel) {
    manual.value = true;
    level.value = next;
    applyDom(next);
    localStorage.setItem(STORAGE_KEY, next);
  }

  function followSystem() {
    manual.value = false;
    localStorage.removeItem(STORAGE_KEY);
    const next = levelFromSystem();
    level.value = next;
    applyDom(next);
  }

  const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
  const onMq = () => {
    if (manual.value) return;
    const next = levelFromSystem();
    level.value = next;
    applyDom(next);
  };
  mq.addEventListener("change", onMq);
  onScopeDispose(() => mq.removeEventListener("change", onMq));

  function duration(token: QueryaMotionToken | number = "standard"): number {
    const ms = typeof token === "number" ? token : QueryaMotionMs[token];
    return effectiveDurationMs(level.value, ms);
  }

  function easing(name: keyof typeof QueryaMotionEasing = "standard"): string {
    return effectiveEasing(level.value, QueryaMotionEasing[name]);
  }

  const springsOn = computed(() => springsEnabled(level.value));

  const api: MotionApi = {
    level,
    manual,
    setLevel,
    followSystem,
    duration,
    easing,
    springsOn,
  };
  provide(MotionKey, api);
  return api;
}

export function useQueryaMotion(): MotionApi {
  const api = inject(MotionKey);
  if (!api) {
    throw new Error(
      "useQueryaMotion() requires provideQueryaMotion() in an ancestor",
    );
  }
  return api;
}
