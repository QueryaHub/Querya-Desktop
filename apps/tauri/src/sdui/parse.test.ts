import { describe, expect, it } from "vitest";
import { parseSduiPanel, SduiParseError } from "./parse";
import { SAMPLE_HELLO_PANEL_DESCRIPTOR } from "./sampleHelloPanel";

describe("parseSduiPanel", () => {
  it("accepts the sample hello-panel descriptor", () => {
    const panel = parseSduiPanel(
      JSON.parse(JSON.stringify(SAMPLE_HELLO_PANEL_DESCRIPTOR)),
    );
    expect(panel.type).toBe("panel");
    expect(panel.id).toBe("querya.hello-panel");
    expect(panel.title).toBe("Hello panel");
    expect(panel.children.length).toBeGreaterThanOrEqual(4);
    const stack = panel.children.find((n) => n.type === "stack");
    expect(stack?.type).toBe("stack");
    if (stack?.type === "stack") {
      expect(stack.children.some((c) => c.type === "button")).toBe(true);
    }
  });

  it("rejects non-panel roots", () => {
    expect(() => parseSduiPanel({ type: "text", text: "x" })).toThrow(
      SduiParseError,
    );
  });

  it("rejects unknown node types", () => {
    expect(() =>
      parseSduiPanel({
        type: "panel",
        children: [{ type: "wizard", steps: [] }],
      }),
    ).toThrow(/unknown/);
  });
});
