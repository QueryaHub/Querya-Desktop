export type QueryaThemeMode = "system" | "light" | "dark";

const STORAGE_KEY = "querya.theme";

export function readStoredTheme(): QueryaThemeMode {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (raw === "light" || raw === "dark" || raw === "system") return raw;
  return "system";
}

export function applyTheme(mode: QueryaThemeMode): void {
  const root = document.documentElement;
  if (mode === "system") {
    root.removeAttribute("data-theme");
  } else {
    root.setAttribute("data-theme", mode);
  }
  localStorage.setItem(STORAGE_KEY, mode);
}

export function initTheme(): QueryaThemeMode {
  const mode = readStoredTheme();
  applyTheme(mode);
  return mode;
}
