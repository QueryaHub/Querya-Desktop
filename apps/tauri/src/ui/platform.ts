import { invoke } from "@tauri-apps/api/core";
import type { QueryaMotionLevel } from "../motion/types";

export type QueryaPlatform = "macos" | "windows" | "linux" | "unknown";

/** Window chrome control placement by platform convention. */
export type WindowControlsSide = "left" | "right";

/** UA fallback only — prefer `resolvePlatform()` / Rust `host_platform`. */
export function detectPlatformFromUa(): QueryaPlatform {
  const ua = navigator.userAgent.toLowerCase();
  // Linux WebKit sometimes mentions "X11" without "linux".
  if (ua.includes("mac os") || ua.includes("macintosh")) return "macos";
  if (ua.includes("windows") || ua.includes("win64") || ua.includes("win32")) {
    return "windows";
  }
  if (ua.includes("linux") || ua.includes("x11") || ua.includes("wayland")) {
    return "linux";
  }
  return "unknown";
}

/** @deprecated use detectPlatformFromUa or resolvePlatform */
export function detectPlatform(): QueryaPlatform {
  return detectPlatformFromUa();
}

export function platformFromOsString(os: string): QueryaPlatform {
  switch (os.toLowerCase()) {
    case "macos":
    case "darwin":
      return "macos";
    case "windows":
    case "win32":
      return "windows";
    case "linux":
      return "linux";
    default:
      return "unknown";
  }
}

/**
 * macOS → traffic lights on the left.
 * Windows / Linux / unknown → caption buttons on the right.
 */
export function windowControlsSide(platform: QueryaPlatform): WindowControlsSide {
  return platform === "macos" ? "left" : "right";
}

/**
 * macOS uses system traffic lights (`titleBarStyle: Overlay`).
 * Win/Linux draw custom caption buttons in the HTML title bar.
 */
export function usesNativeTrafficLights(platform: QueryaPlatform): boolean {
  return platform === "macos";
}

export function applyPlatformDataset(platform: QueryaPlatform): void {
  const root = document.documentElement;
  root.dataset.platform = platform;
  root.dataset.windowControls = windowControlsSide(platform);
  root.dataset.nativeTrafficLights = String(usesNativeTrafficLights(platform));
}

/** Resolve OS via Rust, fall back to UA when not in Tauri. */
export async function resolvePlatform(): Promise<QueryaPlatform> {
  try {
    const os = await invoke<string>("host_platform");
    return platformFromOsString(os);
  } catch {
    return detectPlatformFromUa();
  }
}

/**
 * Whether heavy glass blur is allowed for the current motion budget.
 * Callers can skip mounting large glass surfaces when false.
 */
export function glassEffectsAllowed(level: QueryaMotionLevel): boolean {
  return level === "full";
}
