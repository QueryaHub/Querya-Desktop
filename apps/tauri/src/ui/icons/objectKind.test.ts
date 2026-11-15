import { describe, expect, it } from "vitest";
import { connectionAsset } from "./registry";
import { iconForDriver, iconForObjectNode } from "./objectKind";

describe("iconForObjectNode", () => {
  it("maps relation kinds to Flutter QueryaIcons leaves", () => {
    expect(iconForObjectNode("table")).toBe("table");
    expect(iconForObjectNode("view")).toBe("view");
    expect(iconForObjectNode("materialized_view")).toBe("materializedView");
    expect(iconForObjectNode("schema")).toBe("schema");
  });

  it("maps named schema folders to Flutter group icons", () => {
    expect(iconForObjectNode("folder", "Tables")).toBe("tableGroup");
    expect(iconForObjectNode("folder", "Triggers")).toBe("trigger");
    expect(iconForObjectNode("folder", "Other")).toBe("folder");
  });
});

describe("iconForDriver / connectionAsset", () => {
  it("uses Flutter connectionAsset PNGs for built-in drivers", () => {
    expect(connectionAsset("postgres")).toBe("/drivers/postgresql_icon.png");
    expect(connectionAsset("mysql")).toBe("/drivers/mysql_icon.png");
    expect(connectionAsset("redis")).toBe("/drivers/redis_icon.png");
    expect(connectionAsset("mongodb")).toBe("/drivers/mongodb_icon.png");
    expect(connectionAsset("sqlite")).toBeNull();
  });

  it("falls back to Flutter connectionIcon Material names", () => {
    expect(iconForDriver("postgres")).toBe("database");
    expect(iconForDriver("sqlite")).toBe("sqlite");
    expect(iconForDriver("mysql")).toBe("tableGroup");
    expect(iconForDriver("postgres", { mock: true })).toBe("demo");
  });
});
