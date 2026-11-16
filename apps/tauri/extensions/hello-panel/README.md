# Hello Panel sample extension

Minimal Querya extension that speaks NDJSON JSON-RPC over stdio and returns an
SDUI panel descriptor (`panel.get`) for the Vue host renderer (#1905).

## Layout

| Path | Role |
| --- | --- |
| `manifest.json` | Package id `querya.hello-panel`, command `helloPanel.open` |
| `querya-ext-hello-panel` (Cargo bin) | Process entry (`main`) |

The executable lives in the Tauri crate as `querya-ext-hello-panel` (same package
as the desktop host). This folder is the marketplace-shaped sample package.

## Build

From the repo root:

```bash
cd apps/tauri/src-tauri
cargo build --bin querya-ext-hello-panel
```

Binary: `apps/tauri/src-tauri/target/debug/querya-ext-hello-panel`
(or `target/release/…` after `--release`).

## Run against the host (manual)

1. Start the Tauri app (`cd apps/tauri && pnpm tauri dev`).
2. Command Palette (`Ctrl/Cmd+P`) → **Open Hello Panel Extension**.
3. Host resolves the binary (see below), runs `system.handshake`, then
   `panel.get`, and renders the descriptor with `SduiPanelRenderer`.
4. **Dismiss** stops the session (`system.shutdown`).

Override the binary path if needed:

```bash
export QUERYA_HELLO_PANEL_BIN=/absolute/path/to/querya-ext-hello-panel
```

Without the env var, the host looks next to the running app / Cargo target
output (`ext_hello_panel_executable`).

## RPC surface

| Method | Result |
| --- | --- |
| `system.handshake` | `{ protocolVersion, extensionId }` |
| `system.ping` | `"pong"` |
| `panel.get` | SDUI `panel` descriptor (title, text, actions) |
| `system.shutdown` | `{ ok: true }` then process exit |

## Automated check

```bash
cd apps/tauri/src-tauri
cargo test --test extension_hello_panel
```
