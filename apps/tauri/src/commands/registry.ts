export type AppCommand = {
  id: string;
  title: string;
  subtitle?: string;
  keywords?: string[];
  run: () => void;
};

export type CommandHandlers = {
  openPreferences: () => void;
  toggleSidebar: () => void;
  openTour: () => void;
  openAbout: () => void;
  openPalette: () => void;
  openQuickSwitcher: () => void;
  launchDemo: () => void;
  openSqlite: () => void;
  newConnection: () => void;
  checkUpdates: () => void;
  goHome: () => void;
};

export function buildCoreCommands(h: CommandHandlers): AppCommand[] {
  return [
    {
      id: "prefs",
      title: "Open Preferences",
      subtitle: "Ctrl/Cmd+,",
      keywords: ["settings", "preferences"],
      run: h.openPreferences,
    },
    {
      id: "palette",
      title: "Command Palette",
      subtitle: "Ctrl/Cmd+P",
      keywords: ["commands"],
      run: h.openPalette,
    },
    {
      id: "goto",
      title: "Go to Object…",
      subtitle: "Ctrl/Cmd+K",
      keywords: ["quick", "switcher", "table"],
      run: h.openQuickSwitcher,
    },
    {
      id: "sidebar",
      title: "Toggle Sidebar",
      subtitle: "Ctrl/Cmd+B",
      keywords: ["panel", "servers"],
      run: h.toggleSidebar,
    },
    {
      id: "home",
      title: "Go Home",
      keywords: ["overview", "connection"],
      run: h.goHome,
    },
    {
      id: "demo",
      title: "Launch Demo Playground",
      keywords: ["demo", "sample"],
      run: h.launchDemo,
    },
    {
      id: "sqlite",
      title: "Open SQLite File…",
      keywords: ["file", "database"],
      run: h.openSqlite,
    },
    {
      id: "new-conn",
      title: "New Connection",
      subtitle: "Ctrl/Cmd+N",
      keywords: ["connect"],
      run: h.newConnection,
    },
    {
      id: "tour",
      title: "Welcome Tour",
      keywords: ["onboarding", "help"],
      run: h.openTour,
    },
    {
      id: "about",
      title: "About Querya",
      keywords: ["version"],
      run: h.openAbout,
    },
    {
      id: "updates",
      title: "Check for Updates…",
      keywords: ["updater"],
      run: h.checkUpdates,
    },
  ];
}

export function filterCommands(
  commands: AppCommand[],
  query: string,
): AppCommand[] {
  const q = query.trim().toLowerCase();
  if (!q) return commands;
  return commands.filter((c) => {
    const hay = [c.title, c.subtitle ?? "", ...(c.keywords ?? [])]
      .join(" ")
      .toLowerCase();
    return hay.includes(q);
  });
}
