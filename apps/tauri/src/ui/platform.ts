import type { QueryaMotionLevel } from "../motion/types";

export type QueryaPlatform = "macos" | "windows" | "linux" | "unknown";

/** Best-effort OS label for CSS `data-platform` (no native plugin required). */
export function detectPlatform(): QueryaPlatform {
  const ua = navigator.userAgent.toLowerCase();
  if (ua.includes("mac")) return "macos";
  if (ua.includes("win")) return "windows";
  if (ua.includes("linux")) return "linux";
  return "unknown";
}

export function applyPlatformDataset(
  platform: QueryaPlatform = detectPlatform(),
): void {
  document.documentElement.dataset.platform = platform;
}

/**
 * Whether heavy glass blur is allowed for the current motion budget.
 * Callers can skip mounting large glass surfaces when false.
 */
export function glassEffectsAllowed(level: QueryaMotionLevel): boolean {
  return level === "full";
}
