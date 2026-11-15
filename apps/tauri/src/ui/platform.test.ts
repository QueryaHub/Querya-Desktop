import { describe, expect, it } from "vitest";
import {
  platformFromOsString,
  usesNativeTrafficLights,
  windowControlsSide,
} from "./platform";

describe("window chrome platform helpers", () => {
  it("maps OS strings to platforms", () => {
    expect(platformFromOsString("macos")).toBe("macos");
    expect(platformFromOsString("darwin")).toBe("macos");
    expect(platformFromOsString("windows")).toBe("windows");
    expect(platformFromOsString("linux")).toBe("linux");
    expect(platformFromOsString("freebsd")).toBe("unknown");
  });

  it("places controls left only on macOS", () => {
    expect(windowControlsSide("macos")).toBe("left");
    expect(windowControlsSide("windows")).toBe("right");
    expect(windowControlsSide("linux")).toBe("right");
    expect(windowControlsSide("unknown")).toBe("right");
  });

  it("uses native traffic lights only on macOS", () => {
    expect(usesNativeTrafficLights("macos")).toBe(true);
    expect(usesNativeTrafficLights("windows")).toBe(false);
    expect(usesNativeTrafficLights("linux")).toBe(false);
    expect(usesNativeTrafficLights("unknown")).toBe(false);
  });
});
