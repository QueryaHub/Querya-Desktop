import type { Theme } from "@glideapps/glide-data-grid";

/** Read a Querya CSS token as a concrete color (Glide paints on canvas). */
function cssVar(name: string, fallback: string): string {
  if (typeof document === "undefined") return fallback;
  const v = getComputedStyle(document.documentElement)
    .getPropertyValue(name)
    .trim();
  return v || fallback;
}

function withAlpha(hexOrCss: string, alpha: number): string {
  const m = /^#([0-9a-f]{6})$/i.exec(hexOrCss.trim());
  if (!m) return hexOrCss;
  const n = parseInt(m[1]!, 16);
  const r = (n >> 16) & 255;
  const g = (n >> 8) & 255;
  const b = n & 255;
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function parseRgb(hexOrCss: string): [number, number, number] | null {
  const m = /^#([0-9a-f]{6})$/i.exec(hexOrCss.trim());
  if (!m) return null;
  const n = parseInt(m[1]!, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/** Opaque blend of `overlay` onto `base` (Glide needs solid `bgCell`). */
function mixOnto(base: string, overlay: string, alpha: number): string {
  const b = parseRgb(base);
  const o = parseRgb(overlay);
  if (!b || !o) return base;
  const mix = (x: number, y: number) => Math.round(x * (1 - alpha) + y * alpha);
  const r = mix(b[0], o[0]);
  const g = mix(b[1], o[1]);
  const bl = mix(b[2], o[2]);
  return `#${((1 << 24) | (r << 16) | (g << 8) | bl).toString(16).slice(1)}`;
}

/**
 * Glide theme from Querya workbench tokens — Flutter darkDefault parity
 * (near-black canvas, cyan accent) and lightDefault when `data-theme=light`.
 */
export function buildQueryaGlideTheme(): Partial<Theme> {
  const fg = cssVar("--q-foreground", "#f8fafc");
  const mutedFg = cssVar("--q-muted-foreground", "#94a3b8");
  const muted = cssVar("--q-muted", "#18181b");
  const surface = cssVar("--q-editor-bg", cssVar("--q-surface", "#0c0c0c"));
  const canvas = cssVar("--q-canvas", "#000000");
  const border = cssVar("--q-border", "#27272a");
  const primary = cssVar("--q-primary", "#22d3ee");
  const primaryFg = cssVar("--q-primary-foreground", "#0a0a0a");
  const accent = cssVar("--q-accent", "#27272a");
  const mono = cssVar(
    "--q-font-mono",
    '"JetBrains Mono", "SF Mono", ui-monospace, monospace',
  );
  const sans = cssVar(
    "--q-font-sans",
    '"Segoe UI", "SF Pro Text", system-ui, sans-serif',
  );
  // Flutter: scheme.muted @ 0.12 on odd rows. When muted ≈ cell surface
  // (dark zinc), blend muted-foreground so the chessboard stays readable.
  const stripeSrc =
    muted.toLowerCase() === surface.toLowerCase() ? mutedFg : muted;
  const bgCellStriped = mixOnto(surface, stripeSrc, 0.12);

  return {
    accentColor: primary,
    accentFg: primaryFg,
    accentLight: withAlpha(primary, 0.16),
    textDark: fg,
    textMedium: mutedFg,
    textLight: mutedFg,
    textBubble: fg,
    bgIconHeader: mutedFg,
    fgIconHeader: fg,
    textHeader: mutedFg,
    textGroupHeader: mutedFg,
    textHeaderSelected: primaryFg,
    bgCell: surface,
    /** Odd-row zebra fill (consumed by `getRowThemeOverride`). */
    bgCellMedium: bgCellStriped,
    bgHeader: canvas,
    bgHeaderHasFocus: accent,
    bgHeaderHovered: accent,
    bgBubble: accent,
    bgBubbleSelected: surface,
    bgSearchResult: withAlpha(primary, 0.18),
    borderColor: withAlpha(border, 0.55),
    horizontalBorderColor: withAlpha(border, 0.35),
    headerBottomBorderColor: withAlpha(border, 0.55),
    drilldownBorder: "transparent",
    linkColor: primary,
    fontFamily: `${sans}, ${mono}`,
    headerFontStyle: "600 12px",
    baseFontStyle: "12px",
    markerFontStyle: "10px",
    editorFontSize: "12px",
    cellHorizontalPadding: 8,
    cellVerticalPadding: 4,
    lineHeight: 1.35,
  };
}

/** Fire when `data-theme` or OS color-scheme changes (token values update). */
export function subscribeThemeChanges(onChange: () => void): () => void {
  const root = document.documentElement;
  const mo = new MutationObserver((mutations) => {
    if (mutations.some((m) => m.attributeName === "data-theme")) onChange();
  });
  mo.observe(root, { attributes: true, attributeFilter: ["data-theme"] });
  const mq = window.matchMedia("(prefers-color-scheme: dark)");
  const onMq = () => onChange();
  mq.addEventListener("change", onMq);
  return () => {
    mo.disconnect();
    mq.removeEventListener("change", onMq);
  };
}
