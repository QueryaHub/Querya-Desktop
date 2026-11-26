import { invoke } from "@tauri-apps/api/core";

export type McpStatus = {
  running: boolean;
  port: number | null;
  sessionCount: number;
  endpointPath: string;
};

export type McpClientKind = "claude" | "cursor" | "vscode" | "generic";

export async function mcpStart(): Promise<McpStatus> {
  return invoke<McpStatus>("mcp_start");
}

export async function mcpStop(): Promise<McpStatus> {
  return invoke<McpStatus>("mcp_stop");
}

export async function mcpStatus(): Promise<McpStatus> {
  return invoke<McpStatus>("mcp_status");
}

/** Best-effort path to the stdio shim next to the desktop binary. */
export function defaultMcpShimPath(): string {
  const name =
    typeof navigator !== "undefined" && /Win/i.test(navigator.userAgent)
      ? "querya-mcp.exe"
      : "querya-mcp";
  return name;
}

export async function mcpShimExecutable(): Promise<string> {
  try {
    return await invoke<string>("mcp_shim_executable");
  } catch {
    return defaultMcpShimPath();
  }
}

export function mcpClientSnippet(
  kind: McpClientKind,
  shimPath: string,
): string {
  const path = shimPath.trim() || defaultMcpShimPath();
  const body =
    kind === "vscode"
      ? {
          servers: {
            querya: { type: "stdio", command: path },
          },
        }
      : {
          mcpServers: {
            querya: { command: path },
          },
        };
  return `${JSON.stringify(body, null, 2)}\n`;
}
