import { describe, expect, it } from "vitest";
import { mcpClientSnippet } from "./mcp";

describe("mcpClientSnippet", () => {
  it("builds Claude / Cursor mcpServers shape", () => {
    const json = JSON.parse(mcpClientSnippet("cursor", "/opt/querya-mcp"));
    expect(json.mcpServers.querya.command).toBe("/opt/querya-mcp");
  });

  it("builds VS Code servers shape", () => {
    const json = JSON.parse(mcpClientSnippet("vscode", "/opt/querya-mcp"));
    expect(json.servers.querya).toEqual({
      type: "stdio",
      command: "/opt/querya-mcp",
    });
  });
});
