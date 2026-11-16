import { describe, expect, it, vi } from "vitest";
import { buildCoreCommands, filterCommands } from "./registry";

const noop = () => undefined;

describe("command registry", () => {
  const commands = buildCoreCommands({
    openPreferences: noop,
    toggleSidebar: noop,
    openTour: noop,
    openAbout: noop,
    openSduiSample: noop,
    openHelloPanel: noop,
    openPalette: noop,
    openQuickSwitcher: noop,
    launchDemo: noop,
    openSqlite: noop,
    newConnection: noop,
    checkUpdates: noop,
    goHome: noop,
  });

  it("includes core built-ins", () => {
    const ids = commands.map((c) => c.id);
    expect(ids).toContain("prefs");
    expect(ids).toContain("palette");
    expect(ids).toContain("goto");
    expect(ids).toContain("tour");
  });

  it("filters by title and keywords", () => {
    expect(filterCommands(commands, "prefer").map((c) => c.id)).toContain(
      "prefs",
    );
    expect(filterCommands(commands, "table").map((c) => c.id)).toContain(
      "goto",
    );
    const run = vi.fn();
    const patched = commands.map((c) =>
      c.id === "demo" ? { ...c, run } : c,
    );
    filterCommands(patched, "demo")[0]?.run();
    expect(run).toHaveBeenCalledOnce();
  });
});
