import { computed, inject, provide, ref, type InjectionKey, type Ref } from "vue";
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
  setLevel: (level: QueryaMotionLevel) => void;
  duration: (token?: QueryaMotionToken | number) => number;
  easing: (name?: keyof typeof QueryaMotionEasing) => string;
  springsOn: Ref<boolean>;
};

const MotionKey: InjectionKey<MotionApi> = Symbol("querya-motion");

function readStoredLevel(): QueryaMotionLevel {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (raw === "full" || raw === "reduced" || raw === "off") return raw;
  return "full";
}

export function provideQueryaMotion(
  initial: QueryaMotionLevel = readStoredLevel(),
): MotionApi {
  const level = ref<QueryaMotionLevel>(initial);

  function applyDom(next: QueryaMotionLevel) {
    document.documentElement.dataset.motion = next;
    localStorage.setItem(STORAGE_KEY, next);
  }

  applyDom(level.value);

  function setLevel(next: QueryaMotionLevel) {
    level.value = next;
    applyDom(next);
  }

  function duration(token: QueryaMotionToken | number = "standard"): number {
    const ms = typeof token === "number" ? token : QueryaMotionMs[token];
    return effectiveDurationMs(level.value, ms);
  }

  function easing(name: keyof typeof QueryaMotionEasing = "standard"): string {
    return effectiveEasing(level.value, QueryaMotionEasing[name]);
  }

  const springsOn = computed(() => springsEnabled(level.value));

  const api: MotionApi = { level, setLevel, duration, easing, springsOn };
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
