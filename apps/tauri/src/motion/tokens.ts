import type { QueryaMotionLevel, SpringDescription } from "./types";

/** Duration tokens — Flutter `QueryaMotion` (ms). */
export const QueryaMotionMs = {
  instant: 0,
  fast: 120,
  standard: 200,
  slow: 320,
  treeExpand: 200,
  sidebarCubic: 160,
} as const;

export type QueryaMotionToken = keyof typeof QueryaMotionMs;

/** CSS easing — Flutter curve counterparts. */
export const QueryaMotionEasing = {
  enter: "cubic-bezier(0.33, 1, 0.68, 1)",
  exit: "cubic-bezier(0.32, 0, 0.67, 0)",
  standard: "cubic-bezier(0.65, 0, 0.35, 1)",
  emphasized: "cubic-bezier(0.2, 0, 0, 1)",
  linear: "linear",
} as const;

/** Spring presets — Flutter `QueryaSpring`. */
export const QueryaSpring: Record<"snappy" | "gentle" | "bouncy", SpringDescription> =
  {
    snappy: { mass: 1, stiffness: 400, damping: 40 },
    gentle: { mass: 1, stiffness: 180, damping: 26.83 },
    bouncy: { mass: 1, stiffness: 300, damping: 20 },
  };

export function effectiveDurationMs(
  level: QueryaMotionLevel,
  tokenMs: number,
): number {
  if (tokenMs <= 0) return 0;
  switch (level) {
    case "off":
      return 0;
    case "reduced": {
      const halved = Math.floor(tokenMs / 2);
      return halved <= 0 ? QueryaMotionMs.fast : halved;
    }
    case "full":
      return tokenMs;
  }
}

export function effectiveEasing(
  level: QueryaMotionLevel,
  easing: string = QueryaMotionEasing.standard,
): string {
  return level === "off" ? QueryaMotionEasing.linear : easing;
}

/** Springs only in Full (Flutter `QueryaSpring.springsEnabled`). */
export function springsEnabled(level: QueryaMotionLevel): boolean {
  return level === "full";
}
