import { invoke } from "@tauri-apps/api/core";
import type { SduiPanelNode } from "../sdui";
import { parseSduiPanel } from "../sdui";

export type ExtensionSessionInfo = {
  sessionId: string;
  extensionId: string;
  protocolVersion: unknown;
  executable: string;
};

export async function resolveHelloPanelExecutable(): Promise<string> {
  return invoke<string>("ext_hello_panel_executable");
}

export async function extHostStart(opts: {
  sessionId: string;
  executable: string;
  args?: string[];
  handshakeParams?: Record<string, unknown>;
}): Promise<ExtensionSessionInfo> {
  return invoke<ExtensionSessionInfo>("ext_host_start", {
    sessionId: opts.sessionId,
    executable: opts.executable,
    args: opts.args ?? [],
    handshakeParams: opts.handshakeParams ?? {},
  });
}

export async function extHostCall(
  sessionId: string,
  method: string,
  params?: unknown,
): Promise<unknown> {
  return invoke("ext_host_call", { sessionId, method, params: params ?? null });
}

export async function extHostStop(sessionId: string): Promise<void> {
  await invoke("ext_host_stop", { sessionId });
}

const HELLO_SESSION = "hello-panel";

/** Start hello-panel, fetch SDUI descriptor, leave session running for the caller. */
export async function mountHelloPanel(): Promise<{
  sessionId: string;
  descriptor: SduiPanelNode;
}> {
  const executable = await resolveHelloPanelExecutable();
  await extHostStop(HELLO_SESSION).catch(() => undefined);
  await extHostStart({
    sessionId: HELLO_SESSION,
    executable,
    handshakeParams: {
      queryaVersion: "0.1.0",
      pluginId: "querya.hello-panel",
    },
  });
  try {
    const raw = await extHostCall(HELLO_SESSION, "panel.get");
    const descriptor = parseSduiPanel(raw);
    return { sessionId: HELLO_SESSION, descriptor };
  } catch (err) {
    await extHostStop(HELLO_SESSION).catch(() => undefined);
    throw err;
  }
}
