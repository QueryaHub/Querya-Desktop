import { describe, expect, it } from "vitest";
import { iconForDriver, iconForObjectNode } from "./objectKind";

describe("iconForObjectNode", () => {
  it("maps relation kinds", () => {
    expect(iconForObjectNode("table")).toBe("table");
    expect(iconForObjectNode("view")).toBe("view");
    expect(iconForObjectNode("materialized_view")).toBe("materializedView");
    expect(iconForObjectNode("schema")).toBe("schema");
  });

  it("maps named schema folders", () => {
    expect(iconForObjectNode("folder", "Tables")).toBe("tableGroup");
    expect(iconForObjectNode("folder", "Triggers")).toBe("trigger");
    expect(iconForObjectNode("folder", "Other")).toBe("folder");
  });
});

describe("iconForDriver", () => {
  it("picks driver and demo glyphs", () => {
    expect(iconForDriver("postgres")).toBe("database");
    expect(iconForDriver("sqlite")).toBe("hardDrive");
    expect(iconForDriver("postgres", { mock: true })).toBe("demo");
  });
});
